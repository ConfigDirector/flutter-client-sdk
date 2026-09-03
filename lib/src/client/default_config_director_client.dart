import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../constants.dart' as constants;
import '../errors.dart';
import '../lifecycle.dart';
import '../logger.dart';
import '../platform/app_info.dart';
import '../platform/user_agent.dart';
import '../telemetry/event_reporter.dart';
import '../telemetry/reporter_factory.dart';
import '../telemetry/telemetry_client.dart';
import '../telemetry/telemetry_event_collector.dart';
import '../telemetry/telemetry_events.dart';
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
    http.Client? httpClient,
    TransportFactory? transportFactory,
    AppLifecycleWatcher? lifecycleWatcher,
    ConnectionRetryDelay? connectionRetryDelay,
    String? Function()? userAgentResolver,
    AppInfoResolver? appInfoResolver,
    TelemetryClient? telemetryClient,
  }) : _logger = options?.logger ?? ConsoleLogger(),
       _timeout = options?.connection.timeout ?? const Duration(seconds: 3) {
    _validateSdkKey(clientSdkKey);

    final connection = options?.connection ?? const ConnectionOptions();
    final baseUrl = _resolveBaseUrl(connection.baseUrl);
    _telemetry =
        telemetryClient ??
        TelemetryEventCollector(
          logger: _logger,
          reporter: createEventReporter(
            sdkKey: clientSdkKey,
            baseUrl: baseUrl,
            metaContext: const TelemetryMetaContext(
              sdkName: constants.sdkName,
              sdkVersion: constants.sdkVersion,
            ),
            logger: _logger,
          ),
        );

    final transportOptions = _transportOptions = TransportOptions(
      clientSdkKey: clientSdkKey,
      baseUrl: baseUrl,
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

    _pauseWhileBackgrounded = connection.pauseWhileBackgrounded;
    _lifecycleWatcher =
        lifecycleWatcher ?? WidgetsBindingLifecycleWatcher(_logger);
    _lifecycleWatcher!.start(_handleLifecycleState);

    _appInfoResolved = _resolveAppInfo(
      options?.metadata,
      appInfoResolver ?? resolveAppInfo,
    );
  }

  final ConfigDirectorLogger _logger;
  final Duration _timeout;

  late final TransportOptions _transportOptions;
  late final Transport _transport;
  late final TelemetryClient _telemetry;
  late final bool _pauseWhileBackgrounded;

  /// Completes once the app name and version have been filled in on
  /// [_transportOptions], whether or not the platform reported them.
  late final Future<void> _appInfoResolved;
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
  ConfigDirectorContext? _requestedContext;
  Completer<void>? _readyCompleter;
  int _connectionGeneration = 0;
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
      _connect(_requestedContext, ClientConnectAction.networkResume);

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
    unawaited(_telemetry.close());
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
    final generation = ++_connectionGeneration;
    try {
      _ready = false;
      _hasConnected = true;
      _pendingAction = action;
      _requestedContext = context;
      final readyCompleter = Completer<void>();
      _readyCompleter = readyCompleter;

      await _appInfoResolved;
      final stopwatch = Stopwatch()..start();
      await _transport.connect(
        context ?? const ConfigDirectorContext(),
        _timeout,
      );
      if (generation != _connectionGeneration) {
        return;
      }
      _currentContext = context;
      unawaited(_telemetry.updateContext(context));
      _emit(_contextUpdated, ContextUpdatedEvent(context));

      final remaining = _timeout - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await readyCompleter.future.timeout(remaining, onTimeout: () {});
      }

      if (!_ready && generation == _connectionGeneration) {
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

  /// Fills in whichever of the app name and version the application did not
  /// provide with the value the platform reports for the running application.
  ///
  /// The platform is not consulted at all when both were provided. Failures are
  /// not fatal: the SDK reports whatever it has and carries on connecting.
  Future<void> _resolveAppInfo(
    ConfigDirectorMetaContext? provided,
    AppInfoResolver resolver,
  ) async {
    var appName = provided?.appName;
    var appVersion = provided?.appVersion;

    if (appName == null || appVersion == null) {
      try {
        final detected = await resolver().timeout(_timeout);
        appName ??= detected.appName;
        appVersion ??= detected.appVersion;
      } on Object catch (error, stackTrace) {
        _logger.debug(
          '[ConfigDirectorClient] Failed to read the app name and version from the platform',
          error,
          stackTrace,
        );
      }

      final metaContext = _transportOptions.metaContext;
      _transportOptions.metaContext = metaContext.withMetadata(
        ConfigDirectorMetaContext(appName: appName, appVersion: appVersion),
      );
    }

    final missing = [
      if (appName == null) 'name',
      if (appVersion == null) 'version',
    ];
    if (missing.isNotEmpty) {
      final pronoun = missing.length == 1 ? 'it' : 'them';
      _logger.info(
        '[ConfigDirectorClient] The ConfigDirector SDK could not find an app '
        '${missing.join(' and ')}, so targeting rules that use $pronoun will '
        'not match. Provide $pronoun through '
        'ConfigDirectorClientOptions.metadata.',
      );
    }
  }

  void _handleConfigSet(ConfigSet configSet) {
    final keys = configSet.configs.keys.toList(growable: false);
    final current = _configSet;
    final isFull = current == null || configSet.kind == ConfigSetKind.full;
    _configSet = isFull ? configSet : current.mergedWith(configSet);

    _markReady();
    _emit(_configsUpdated, ConfigsUpdatedEvent(keys));
    final affected = isFull ? _watchers.keys.toList(growable: false) : keys;
    for (final key in affected) {
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
      final reason = _ready
          ? EvaluationReason.configStateMissing
          : EvaluationReason.clientNotReady;
      _logger.debug(
        "[ConfigDirectorClient] No config state found for '$configKey', "
        "returning default value '$defaultValue'",
      );
      _telemetry.evaluatedConfig(
        EvaluatedConfigEvent.fromEvaluation(
          contextId: _currentContext?.id,
          key: configKey,
          defaultValue: defaultValue,
          requestedType: requestedTypeOf<T>(defaultValue),
          evaluatedValue: defaultValue,
          usedDefault: true,
          evaluationReason: reason,
        ),
      );
      _emit(
        _configEvaluated,
        ConfigEvaluatedEvent(
          ConfigEvaluation(
            key: configKey,
            value: defaultValue,
            isDefaultValue: true,
            reason: reason,
            context: _currentContext,
          ),
        ),
      );
      return defaultValue;
    }

    final result = parseConfigValue(configState, defaultValue);
    _telemetry.evaluatedConfig(
      EvaluatedConfigEvent.fromEvaluation(
        contextId: _currentContext?.id,
        key: configKey,
        type: configState.type,
        defaultValue: defaultValue,
        requestedType: requestedTypeOf<T>(defaultValue),
        evaluatedValue: result.value,
        evaluatedValueId: result.valueId,
        usedDefault: result.usedDefault,
        evaluationReason: result.reason,
      ),
    );
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
    if (_disposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_telemetry.flush());
        _pauseWhileBackgroundedIfEnabled();
      case AppLifecycleState.hidden:
        unawaited(_telemetry.flush());
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.resumed:
        if (!_pausedWhileBackgrounded) {
          return;
        }
        _pausedWhileBackgrounded = false;
        unawaited(resumeNetwork());
    }
  }

  void _pauseWhileBackgroundedIfEnabled() {
    if (!_pauseWhileBackgrounded ||
        !_hasConnected ||
        _pausedWhileBackgrounded) {
      return;
    }

    _pausedWhileBackgrounded = true;
    pauseNetwork();
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
