import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
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

const int _maxBackoffExponent = 9;

final class _ConfigWatcher {
  _ConfigWatcher({required this.reevaluate, required this.close});

  final void Function() reevaluate;

  final Future<void> Function() close;
}

/// The default [ConfigDirectorClient] implementation.
final class DefaultConfigDirectorClient implements ConfigDirectorClient {
  factory DefaultConfigDirectorClient(
    String clientSdkKey, {
    ConfigDirectorClientOptions? options,
    http.Client? httpClient,
    TransportFactory? transportFactory,
    AppLifecycleWatcher? lifecycleWatcher,
    ConnectionRetryDelay? connectionRetryDelay,
    String? Function()? userAgentResolver,
    AppInfoResolver? appInfoResolver,
    TelemetryClient? telemetryClient,
  }) {
    _validateSdkKey(clientSdkKey);

    final logger = options?.logger ?? ConsoleLogger();
    final connection = options?.connection ?? const ConnectionOptions();
    _validateConnection(connection);
    final baseUrl = _resolveBaseUrl(connection.baseUrl);

    final transportOptions = TransportOptions(
      clientSdkKey: clientSdkKey,
      baseUrl: baseUrl,
      metaContext: SdkMetaContext(
        sdkName: constants.sdkName,
        sdkVersion: constants.sdkVersion,
        metadata: options?.metadata,
        userAgent: (userAgentResolver ?? resolveUserAgent)(),
      ),
      instanceId: const Uuid().v4(),
      logger: logger,
      connectionRetryDelay: connectionRetryDelay ?? _exponentialRetryDelay,
      httpClient: httpClient,
      pollingInterval: connection.pollingInterval,
    );

    return DefaultConfigDirectorClient._(
      logger: logger,
      timeout: connection.timeout,
      telemetry:
          telemetryClient ??
          TelemetryEventCollector(
            logger: logger,
            reporter: createEventReporter(
              sdkKey: clientSdkKey,
              baseUrl: baseUrl,
              metaContext: const TelemetryMetaContext(
                sdkName: constants.sdkName,
                sdkVersion: constants.sdkVersion,
              ),
              logger: logger,
            ),
          ),
      transportOptions: transportOptions,
      transport:
          transportFactory?.call(transportOptions) ??
          _createTransport(connection.mode, transportOptions),
      pauseWhileBackgrounded: connection.pauseWhileBackgrounded,
      lifecycleWatcher:
          lifecycleWatcher ?? WidgetsBindingLifecycleWatcher(logger),
      metadata: options?.metadata,
      appInfoResolver: appInfoResolver ?? resolveAppInfo,
    );
  }

  DefaultConfigDirectorClient._({
    required ConfigDirectorLogger logger,
    required Duration timeout,
    required TelemetryClient telemetry,
    required TransportOptions transportOptions,
    required Transport transport,
    required bool pauseWhileBackgrounded,
    required AppLifecycleWatcher lifecycleWatcher,
    required ConfigDirectorMetaContext? metadata,
    required AppInfoResolver appInfoResolver,
  }) : _logger = logger,
       _timeout = timeout,
       _telemetry = telemetry,
       _transportOptions = transportOptions,
       _transport = transport,
       _pauseWhileBackgrounded = pauseWhileBackgrounded,
       _lifecycleWatcher = lifecycleWatcher {
    _configSetSubscription = _transport.configSets.listen(_handleConfigSet);
    _lifecycleWatcher.start(_handleLifecycleState);
    _appInfoResolved = _resolveAppInfo(metadata, appInfoResolver);
  }

  final ConfigDirectorLogger _logger;
  final Duration _timeout;
  final TelemetryClient _telemetry;
  final TransportOptions _transportOptions;
  final Transport _transport;
  final bool _pauseWhileBackgrounded;
  final AppLifecycleWatcher _lifecycleWatcher;

  late final StreamSubscription<ConfigSet> _configSetSubscription;
  late final Future<void> _appInfoResolved;

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
  Future<void> initialize([ConfigDirectorContext? context]) async {
    _initializing = true;
    await _connect(context, ClientConnectAction.initialization);
    _initializing = false;
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
      if (const DeepCollectionEquality().equals(value, lastEmitted)) {
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

    _lifecycleWatcher.stop();
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
    _connectionGeneration += 1;
    final generation = _connectionGeneration;
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

  static Transport _createTransport(
    ConnectionMode mode,
    TransportOptions options,
  ) => switch (mode) {
    ConnectionMode.streaming => StreamingTransport(options),
    ConnectionMode.polling => PollingTransport(options),
  };

  static Duration _exponentialRetryDelay(int attempt) =>
      Duration(seconds: pow(2, min(attempt, _maxBackoffExponent)).toInt());

  static Uri _resolveBaseUrl(Uri? baseUrl) {
    if (baseUrl == null) {
      return constants.clientBaseUrl;
    }

    if (!baseUrl.isAbsolute) {
      throw ConfigDirectorValidationException(
        "Invalid base URL '$baseUrl'. The base URL must be absolute.",
      );
    }

    return baseUrl;
  }

  static void _validateConnection(ConnectionOptions connection) {
    if (connection.timeout <= Duration.zero) {
      throw ConfigDirectorValidationException(
        "Invalid timeout '${connection.timeout}'. The timeout must be positive.",
      );
    }
    if (connection.mode == ConnectionMode.polling &&
        connection.pollingInterval <= Duration.zero) {
      throw ConfigDirectorValidationException(
        "Invalid polling interval '${connection.pollingInterval}'. The polling "
        'interval must be positive.',
      );
    }
  }

  static void _validateSdkKey(String clientSdkKey) {
    if (clientSdkKey.trim().isEmpty) {
      throw const ConfigDirectorValidationException(
        'No client SDK key was provided, the client cannot be instantiated '
        'without a valid client SDK key',
      );
    }
  }

  void _validateDefaultValue<T extends Object>(T defaultValue) {
    if (defaultValue is Function) {
      throw const ConfigDirectorValidationException(
        'Invalid default value. The default value for a config cannot be a function.',
      );
    }
  }
}
