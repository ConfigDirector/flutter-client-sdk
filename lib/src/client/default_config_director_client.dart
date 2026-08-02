import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../constants.dart' as constants;
import '../errors.dart';
import '../lifecycle.dart';
import '../logger.dart';
import '../platform/user_agent.dart';
import '../transport/polling_transport.dart';
import '../transport/streaming_transport.dart';
import '../transport/transport.dart';
import '../types.dart';
import '../value_parser.dart';
import 'client_events.dart';
import 'client_options.dart';
import 'config_director_client.dart';

/// Builds the transport the client connects with. Injectable for testing.
typedef TransportFactory = Transport Function(TransportOptions options);

/// 2^9 seconds is a little over 8 minutes, which caps the backoff to under 10.
const int _maxExponentialDelay = 9;

/// A single [ConfigDirectorClient.watch] subscription.
final class _ConfigWatcher {
  _ConfigWatcher({required this.reevaluate, required this.close});

  /// Re-evaluates the config and emits the value if it changed.
  final void Function() reevaluate;

  final Future<void> Function() close;
}

/// The default [ConfigDirectorClient] implementation.
final class DefaultConfigDirectorClient implements ConfigDirectorClient {
  DefaultConfigDirectorClient(
    String clientSdkKey, {
    ConfigDirectorClientOptions? options,
    // The parameters below are internal seams for testing and are not part of
    // the supported API surface.
    http.Client? httpClient,
    TransportFactory? transportFactory,
    AppLifecycleWatcher? lifecycleWatcher,
    ConnectionRetryDelay? connectionRetryDelay,
    String? Function()? userAgentResolver,
  }) : _logger = options?.logger ?? ConsoleLogger(),
       _timeout = options?.connection.timeout ?? const Duration(seconds: 3) {
    _validateSdkKey(clientSdkKey);

    final connection = options?.connection ?? const ConnectionOptions();
    final transportOptions = TransportOptions(
      clientSdkKey: clientSdkKey,
      baseUrl: _resolveBaseUrl(connection.baseUrl),
      metaContext: SdkMetaContext(
        sdkName: constants.sdkName,
        sdkVersion: constants.sdkVersion,
        metadata: options?.metadata,
        userAgent: (userAgentResolver ?? resolveUserAgent)(),
      ),
      instanceId: const Uuid().v4(),
      logger: _logger,
      connectionRetryDelay: connectionRetryDelay ?? _exponentialRetryDelay,
      httpClient: httpClient,
      pollingInterval: connection.pollingInterval,
    );

    _transport =
        transportFactory?.call(transportOptions) ??
        _createTransport(connection.mode, transportOptions);
    _configSetSubscription = _transport.configSets.listen(_handleConfigSet);

    if (connection.pauseWhileBackgrounded) {
      _lifecycleWatcher =
          lifecycleWatcher ?? WidgetsBindingLifecycleWatcher(_logger);
      _lifecycleWatcher!.start(_handleLifecycleState);
    }
  }

  final ConfigDirectorLogger _logger;
  final Duration _timeout;

  late final Transport _transport;
  late final StreamSubscription<ConfigSet> _configSetSubscription;
  AppLifecycleWatcher? _lifecycleWatcher;

  final Map<String, List<_ConfigWatcher>> _watchers = {};

  final StreamController<ClientReadyEvent> _clientReady =
      StreamController<ClientReadyEvent>.broadcast();
  final StreamController<ConfigsUpdatedEvent> _configsUpdated =
      StreamController<ConfigsUpdatedEvent>.broadcast();
  final StreamController<ContextUpdatedEvent> _contextUpdated =
      StreamController<ContextUpdatedEvent>.broadcast();
  final StreamController<ConfigEvaluatedEvent> _configEvaluated =
      StreamController<ConfigEvaluatedEvent>.broadcast();

  ConfigSet? _configSet;
  ConfigDirectorContext? _currentContext;
  Completer<void>? _readyCompleter;
  ClientConnectAction _pendingAction = ClientConnectAction.initialization;
  bool _ready = false;
  bool _initializing = false;
  bool _hasConnected = false;
  bool _pausedWhileBackgrounded = false;
  bool _disposed = false;

  @override
  Stream<ClientReadyEvent> get onClientReady => _clientReady.stream;

  @override
  Stream<ConfigsUpdatedEvent> get onConfigsUpdated => _configsUpdated.stream;

  @override
  Stream<ContextUpdatedEvent> get onContextUpdated => _contextUpdated.stream;

  @override
  Stream<ConfigEvaluatedEvent> get onConfigEvaluated => _configEvaluated.stream;

  @override
  ConfigDirectorContext? get context => _currentContext;

  @override
  bool get isReady => _ready;

  @override
  bool get isInitializing => _initializing;

  @override
  Future<void> initialize([ConfigDirectorContext? context]) {
    _initializing = true;
    return _connect(context, ClientConnectAction.initialization);
  }

  @override
  Future<void> updateContext(ConfigDirectorContext context) =>
      _connect(context, ClientConnectAction.contextUpdate);

  @override
  T getValue<T extends Object>(String configKey, T defaultValue) {
    _validateDefaultValue(defaultValue);
    return _evaluate(configKey, _configSet?.configs[configKey], defaultValue);
  }

  @override
  Stream<T> watch<T extends Object>(String configKey, T defaultValue) {
    _validateDefaultValue(defaultValue);

    late final StreamController<T> controller;
    late final _ConfigWatcher watcher;
    T? lastEmitted;

    void emitIfChanged() {
      if (controller.isClosed) {
        return;
      }
      final value = getValue(configKey, defaultValue);
      if (value == lastEmitted) {
        return;
      }
      lastEmitted = value;
      controller.add(value);
    }

    controller = StreamController<T>(
      onListen: () {
        (_watchers[configKey] ??= []).add(watcher);
        emitIfChanged();
      },
      onCancel: () => _watchers[configKey]?.remove(watcher),
    );
    watcher = _ConfigWatcher(
      reevaluate: emitIfChanged,
      close: () => controller.close(),
    );

    return controller.stream;
  }

  @override
  void unwatch(String configKey) {
    final watchers = _watchers.remove(configKey);
    for (final watcher in watchers ?? const <_ConfigWatcher>[]) {
      unawaited(watcher.close());
    }
  }

  @override
  void unwatchAll() {
    for (final configKey in _watchers.keys.toList(growable: false)) {
      unwatch(configKey);
    }
  }

  @override
  void pauseNetwork() {
    _logger.debug(
      '[ConfigDirectorClient] pauseNetwork() called, pausing transport connection',
    );
    _transport.close();
    _ready = false;
  }

  @override
  Future<void> resumeNetwork() =>
      _connect(_currentContext, ClientConnectAction.networkResume);

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;

    _logger.debug(
      '[ConfigDirectorClient] dispose() has been called, closing the connection '
      'to the server and removing all observers',
    );

    _lifecycleWatcher?.stop();
    _lifecycleWatcher = null;
    unawaited(_configSetSubscription.cancel());
    unwatchAll();

    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete();
    }
    _readyCompleter = null;
    _ready = false;

    _transport.dispose();
    unawaited(_clientReady.close());
    unawaited(_configsUpdated.close());
    unawaited(_contextUpdated.close());
    unawaited(_configEvaluated.close());
  }

  Future<void> _connect(
    ConfigDirectorContext? context,
    ClientConnectAction action,
  ) async {
    try {
      _ready = false;
      _hasConnected = true;
      _pendingAction = action;
      final readyCompleter = Completer<void>();
      _readyCompleter = readyCompleter;

      final stopwatch = Stopwatch()..start();
      await _transport.connect(
        context ?? const ConfigDirectorContext(),
        _timeout,
      );
      _currentContext = context;
      _emit(_contextUpdated, ContextUpdatedEvent(context));

      // The transport may have spent part of the budget connecting; only the
      // remainder is left to wait for the first config set.
      final remaining = _timeout - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await readyCompleter.future.timeout(remaining, onTimeout: () {});
      }

      if (!_ready) {
        _logger.warn(
          '[ConfigDirectorClient] Timed out waiting for ${action.description} after '
          '${_timeout.inMilliseconds}ms. The client will continue to retry as long as no '
          'fatal errors are detected. Configs will return the default value until the '
          'connection succeeds.',
        );
      }
    } on Object catch (error, stackTrace) {
      _logger.error(
        '[ConfigDirectorClient] An error occurred during ${action.description}',
        error,
        stackTrace,
      );
    }
  }

  void _handleConfigSet(ConfigSet configSet) {
    final keys = configSet.configs.keys.toList(growable: false);
    final current = _configSet;
    _configSet = current == null || configSet.kind == ConfigSetKind.full
        ? configSet
        : current.mergedWith(configSet);

    _markReady();
    _emit(_configsUpdated, ConfigsUpdatedEvent(keys));
    for (final key in keys) {
      for (final watcher in _watchers[key] ?? const <_ConfigWatcher>[]) {
        watcher.reevaluate();
      }
    }

    _logger.debug(
      '[ConfigDirectorClient] ConfigSet updated from server: $keys',
    );
  }

  void _markReady() {
    final readyCompleter = _readyCompleter;
    if (readyCompleter == null || readyCompleter.isCompleted) {
      return;
    }

    readyCompleter.complete();
    _ready = true;
    _initializing = false;
    _emit(_clientReady, ClientReadyEvent(_pendingAction));
    _logger.debug(
      '[ConfigDirectorClient] Received initial payload from the server, client is ready',
    );
  }

  T _evaluate<T extends Object>(
    String configKey,
    ConfigState? configState,
    T defaultValue,
  ) {
    if (configState == null) {
      _logger.debug(
        "[ConfigDirectorClient] No config state found for '$configKey', "
        "returning default value '$defaultValue'",
      );
      _emit(
        _configEvaluated,
        ConfigEvaluatedEvent(
          ConfigEvaluation(
            key: configKey,
            value: defaultValue,
            isDefaultValue: true,
            reason: _ready
                ? EvaluationReason.configStateMissing
                : EvaluationReason.clientNotReady,
            context: _currentContext,
          ),
        ),
      );
      return defaultValue;
    }

    final result = parseConfigValue(configState, defaultValue);
    _emit(
      _configEvaluated,
      ConfigEvaluatedEvent(
        ConfigEvaluation(
          key: configKey,
          value: result.value,
          valueId: result.valueId,
          isDefaultValue: result.usedDefault,
          reason: result.reason,
          context: _currentContext,
        ),
      ),
    );
    _logger.debug(
      "[ConfigDirectorClient] Evaluated '$configKey' to '${result.value}'",
    );
    return result.value;
  }

  void _handleLifecycleState(AppLifecycleState state) {
    // Nothing to pause or resume until the application has connected once.
    if (!_hasConnected || _disposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_pausedWhileBackgrounded) {
          return;
        }
        _pausedWhileBackgrounded = true;
        pauseNetwork();
      case AppLifecycleState.resumed:
        if (!_pausedWhileBackgrounded) {
          return;
        }
        _pausedWhileBackgrounded = false;
        unawaited(resumeNetwork());
      // `inactive` and `hidden` cover transient interruptions, such as the app
      // switcher or an incoming call, which are not worth dropping a connection
      // over.
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _emit<T>(StreamController<T> controller, T event) {
    if (!controller.isClosed) {
      controller.add(event);
    }
  }

  Transport _createTransport(ConnectionMode mode, TransportOptions options) =>
      switch (mode) {
        ConnectionMode.streaming => StreamingTransport(options),
        ConnectionMode.polling => PollingTransport(options),
        ConnectionMode.oneTime => OneTimeTransport(options),
      };

  static Duration _exponentialRetryDelay(int attempt) =>
      Duration(seconds: pow(2, min(attempt, _maxExponentialDelay)).toInt());

  Uri _resolveBaseUrl(Uri? baseUrl) {
    if (baseUrl == null) {
      return constants.clientBaseUrl;
    }

    if (!baseUrl.isAbsolute) {
      throw ConfigDirectorValidationError(
        "Invalid base URL '$baseUrl'. The base URL must be absolute.",
      );
    }

    return baseUrl;
  }

  void _validateSdkKey(String clientSdkKey) {
    if (clientSdkKey.trim().isEmpty) {
      throw const ConfigDirectorValidationError(
        'No client SDK key was provided, the client cannot be instantiated '
        'without a valid client SDK key',
      );
    }
  }

  void _validateDefaultValue<T extends Object>(T defaultValue) {
    if (defaultValue is Function) {
      throw const ConfigDirectorValidationError(
        'Invalid default value. The default value for a config cannot be a function.',
      );
    }
  }
}
