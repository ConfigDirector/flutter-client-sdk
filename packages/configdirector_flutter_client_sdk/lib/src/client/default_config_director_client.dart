import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../cached_values.dart';
import '../client_session.dart';
import '../context_admission.dart';
import '../errors.dart';
import '../lifecycle.dart';
import '../logger.dart';
import '../platform/app_info.dart';
import '../platform/instance_id_storage.dart';
import '../platform/shared_preferences_caching_provider.dart';
import '../platform/user_agent.dart';
import '../sdk_identity.dart';
import '../telemetry/discarding_telemetry_client.dart';
import '../telemetry/reporter_factory.dart';
import '../telemetry/telemetry_client.dart';
import '../telemetry/telemetry_event_collector.dart';
import '../telemetry/telemetry_events.dart';
import '../transport/offline_transport.dart';
import '../transport/polling_transport.dart';
import '../transport/streaming_transport.dart';
import '../transport/transport.dart';
import '../types.dart';
import '../value_parser.dart';
import 'client_events.dart';
import 'client_options.dart';
import 'config_director_client.dart';
import 'connection_plan.dart';

/// Builds the transport the client connects with. Injectable for testing.
typedef TransportFactory = Transport Function(TransportOptions options);

const int _maxBackoffExponent = 9;

enum _ConfigSetSource { none, cachedValues, livePayload }

final class _ConfigWatcher {
  _ConfigWatcher({required this.reevaluate, required this.close});

  final void Function() reevaluate;

  final Future<void> Function() close;
}

/// The default [ConfigDirectorClient] implementation.
final class DefaultConfigDirectorClient implements ConfigDirectorClient {
  factory DefaultConfigDirectorClient(
    String? clientSdkKey, {
    ConfigDirectorClientOptions? options,
    SdkIdentity identity = flutterClientSdkIdentity,
    http.Client? httpClient,
    TransportFactory? transportFactory,
    AppLifecycleWatcher? lifecycleWatcher,
    ConnectionRetryDelay? connectionRetryDelay,
    String? Function()? userAgentResolver,
    AppInfoResolver? appInfoResolver,
    TelemetryClient? telemetryClient,
    InstanceIdStorage? instanceIdStorage,
    ClientSession? clientSession,
  }) {
    final logger = options?.logger ?? ConsoleLogger();
    final connection = options?.connection ?? const ConnectionOptions();
    final connectionPlan = planConnection(clientSdkKey, connection, logger);
    switch (connectionPlan) {
      case StayOffline(:final source):
        return DefaultConfigDirectorClient._(
          logger: logger,
          connectionPlan: connectionPlan,
          timeout: connection.timeout,
          telemetry: const DiscardingTelemetryClient(),
          transport: OfflineTransport(source),
          pauseWhileBackgrounded: false,
          lifecycleWatcher: const NoLifecycleWatcher(),
          connectPrerequisites: Future.value(),
          cachedValuesStore: null,
        );
      case final Connect live:
        final provisionalSession = clientSession ?? ClientSession.provisional();
        final transportOptions = TransportOptions(
          clientSdkKey: live.clientSdkKey,
          baseUrl: live.baseUrl,
          metaContext: SdkMetaContext(
            sdkName: identity.name,
            sdkVersion: identity.version,
            metadata: options?.metadata,
            userAgent: (userAgentResolver ?? resolveUserAgent)(),
          ),
          clientSession: provisionalSession,
          logger: logger,
          connectionRetryDelay: connectionRetryDelay ?? _exponentialRetryDelay,
          httpClient: httpClient,
          pollingInterval: live.pollingInterval,
        );
        final settledClientSession = clientSession != null
            ? Future.value(clientSession)
            : settleClientSession(
                provisional: provisionalSession,
                storage:
                    instanceIdStorage ?? sharedPreferencesInstanceIdStorage(),
                logger: logger,
              );
        final instanceId = settledClientSession.then(
          (session) => session.instanceId,
        );

        final cachingPlan = planCaching(
          live,
          options?.caching ?? const CachingOptions(),
          sharedPreferencesCachingProvider,
        );

        return DefaultConfigDirectorClient._(
          logger: logger,
          connectionPlan: live,
          timeout: live.timeout,
          telemetry:
              telemetryClient ??
              TelemetryEventCollector(
                logger: logger,
                currentMetaContext: () => transportOptions.metaContext,
                instanceId: instanceId,
                reporter: createEventReporter(
                  sdkKey: live.clientSdkKey,
                  baseUrl: live.baseUrl,
                  logger: logger,
                ),
              ),
          transport:
              transportFactory?.call(transportOptions) ??
              _createTransport(live.mode, transportOptions),
          pauseWhileBackgrounded: connection.pauseWhileBackgrounded,
          lifecycleWatcher:
              lifecycleWatcher ?? WidgetsBindingLifecycleWatcher(logger),
          connectPrerequisites: Future.wait([
            _fillInAppInfo(
              transportOptions,
              provided: options?.metadata,
              resolver: appInfoResolver ?? resolveAppInfo,
              timeout: live.timeout,
              logger: logger,
            ),
            settledClientSession.then(
              (session) => transportOptions.clientSession = session,
            ),
          ]),
          cachedValuesStore: _cachedValuesStoreFor(
            cachingPlan,
            instanceId: instanceId,
            logger: logger,
          ),
        );
    }
  }

  static CachedValuesStore? _cachedValuesStoreFor(
    CachingPlan cachingPlan, {
    required Future<String> instanceId,
    required ConfigDirectorLogger logger,
  }) {
    switch (cachingPlan) {
      case KeepNothing():
        logger.debug(
          '[ConfigDirectorClient] No values are kept on the device: caching '
          'is turned off',
        );
        return null;
      case KeepValues(:final provider, :final clientSdkKeyDigest):
        return CachedValuesStore(
          provider: provider,
          clientSdkKeyDigest: clientSdkKeyDigest,
          instanceId: instanceId,
          logger: logger,
        );
    }
  }

  DefaultConfigDirectorClient._({
    required ConfigDirectorLogger logger,
    required ConnectionPlan connectionPlan,
    required Duration timeout,
    required TelemetryClient telemetry,
    required Transport transport,
    required bool pauseWhileBackgrounded,
    required AppLifecycleWatcher lifecycleWatcher,
    required Future<void> connectPrerequisites,
    required CachedValuesStore? cachedValuesStore,
  }) : _logger = logger,
       _connectionPlan = connectionPlan,
       _timeout = timeout,
       _telemetry = telemetry,
       _transport = transport,
       _pauseWhileBackgrounded = pauseWhileBackgrounded,
       _lifecycleWatcher = lifecycleWatcher,
       _connectPrerequisites = connectPrerequisites,
       _cachedValuesStore = cachedValuesStore {
    _configSetSubscription = _transport.configSets.listen(_applyConfigSet);
    _lifecycleWatcher.start(_followAppLifecycle);
  }

  final ConfigDirectorLogger _logger;
  final ConnectionPlan _connectionPlan;
  final Duration _timeout;
  final TelemetryClient _telemetry;
  final Transport _transport;
  final bool _pauseWhileBackgrounded;
  final AppLifecycleWatcher _lifecycleWatcher;
  final Future<void> _connectPrerequisites;
  final CachedValuesStore? _cachedValuesStore;

  late final StreamSubscription<ConfigSet> _configSetSubscription;

  final Map<String, List<_ConfigWatcher>> _watchers = {};

  final StreamController<ClientReadyEvent> _clientReady =
      StreamController<ClientReadyEvent>.broadcast();
  final StreamController<ConfigsUpdatedEvent> _configsUpdated =
      StreamController<ConfigsUpdatedEvent>.broadcast();
  final StreamController<ContextUpdatedEvent> _contextUpdated =
      StreamController<ContextUpdatedEvent>.broadcast();
  final StreamController<ConfigEvaluatedEvent> _configEvaluated =
      StreamController<ConfigEvaluatedEvent>.broadcast();
  final StreamController<CachedValuesLoadedEvent> _cachedValuesLoaded =
      StreamController<CachedValuesLoadedEvent>.broadcast();

  ConfigSet? _configSet;
  ConfigDirectorContext? _currentContext;
  ConfigDirectorContext? _requestedContext;
  Completer<void>? _readyCompleter;
  int _connectionGeneration = 0;
  ClientConnectAction _pendingAction = ClientConnectAction.initialization;
  bool _ready = false;
  bool _initializing = false;
  _ConfigSetSource _configSetSource = _ConfigSetSource.none;
  bool _cachedValuesAdoptionStarted = false;
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
  Stream<CachedValuesLoadedEvent> get onCachedValuesLoaded =>
      _cachedValuesLoaded.stream;

  @override
  ConfigDirectorContext? get context => _currentContext;

  @override
  bool get isReady => _ready;

  @override
  bool get isInitializing =>
      _initializing && _configSetSource != _ConfigSetSource.livePayload;

  @override
  Future<void> initialize([ConfigDirectorContext? context]) {
    _initializing = true;
    const action = ClientConnectAction.initialization;
    final admittedContext = _admittedContext(context, action);
    switch (_connectionPlan) {
      case Connect():
        final connection = _connect(admittedContext, action);
        _startCachedValuesAdoption();
        return connection;
      case StayOffline():
        return _loadOfflineValues(admittedContext);
    }
  }

  @override
  Future<void> updateContext(ConfigDirectorContext context) {
    const action = ClientConnectAction.contextUpdate;
    final admittedContext = _admittedContext(context, action);
    switch (_connectionPlan) {
      case Connect():
        return _connect(admittedContext, action);
      case StayOffline():
        _adoptContext(admittedContext);
        return Future.value();
    }
  }

  @override
  T getValue<T extends Object>(String configKey, T defaultValue) =>
      evaluate(configKey, defaultValue).value as T;

  @override
  ConfigEvaluation evaluate<T extends Object>(
    String configKey,
    T defaultValue,
  ) {
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
    switch (_connectionPlan) {
      case Connect():
        _logger.debug(
          '[ConfigDirectorClient] pauseNetwork() called, pausing transport connection',
        );
        _transport.close();
        _ready = false;
      case StayOffline():
        return;
    }
  }

  @override
  Future<void> resumeNetwork() => switch (_connectionPlan) {
    Connect() => _connect(_requestedContext, ClientConnectAction.networkResume),
    StayOffline() => Future.value(),
  };

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
    _initializing = false;

    _transport.dispose();
    unawaited(_clientReady.close());
    unawaited(_configsUpdated.close());
    unawaited(_contextUpdated.close());
    unawaited(_configEvaluated.close());
    unawaited(_cachedValuesLoaded.close());
  }

  ConfigDirectorContext? _admittedContext(
    ConfigDirectorContext? suppliedContext,
    ClientConnectAction action,
  ) {
    switch (admissionOf(suppliedContext)) {
      case ContextAdmitted(:final context):
        return context;
      case ContextIgnoredForAnInvalidContextKind(:final contextKindSample):
        _logger.error(
          '[ConfigDirectorClient] Ignored the context supplied for '
          "${action.description} because its context kind '$contextKindSample' "
          'is invalid, so configs are evaluated as if no context was supplied. '
          'A context kind has 1 to 64 characters: lowercase ASCII letters, '
          "digits, '-' and '_'.",
        );
        _telemetry.recordInvalidContextSubmission(contextKindSample);
        return null;
    }
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

      await _connectPrerequisites;
      if (_disposed) {
        return;
      }
      final stopwatch = Stopwatch()..start();
      final outcome = await _transport.connect(
        context ?? const ConfigDirectorContext(),
        _timeout,
        action,
      );
      if (generation != _connectionGeneration) {
        return;
      }
      if (outcome == ConnectOutcome.failedFatally) {
        _initializing = false;
        return;
      }
      _adoptContext(context);

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
      _initializing = false;
      _logger.error(
        '[ConfigDirectorClient] An error occurred during ${action.description}',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _loadOfflineValues(ConfigDirectorContext? context) async {
    _readyCompleter = Completer<void>();
    _adoptContext(context);
    try {
      await _transport.connect(
        context ?? const ConfigDirectorContext(),
        _timeout,
        ClientConnectAction.initialization,
      );
    } on ConfigDirectorInitializationException {
      _initializing = false;
      rethrow;
    }
  }

  void _startCachedValuesAdoption() {
    final store = _cachedValuesStore;
    if (store == null || _cachedValuesAdoptionStarted) {
      return;
    }
    _cachedValuesAdoptionStarted = true;
    unawaited(_adoptCachedValues(store));
  }

  Future<void> _adoptCachedValues(CachedValuesStore store) async {
    final read = await store.read();
    final CachedValues cachedValues;
    switch (read) {
      case NoCachedValues() ||
          CachedValuesInFirstFormat() ||
          CachedValuesUnreadable() ||
          CachedValuesReadFailed():
        return;
      case CachedValuesStored(cachedValues: final stored):
        cachedValues = stored;
    }
    final launchContextTag = await store.contextTagOf(_requestedContext);
    if (_disposed) {
      return;
    }
    final adoption = decideCachedValuesAdoption(
      cachedValues,
      launchContextTag,
      hasReceivedLiveValues: _configSetSource == _ConfigSetSource.livePayload,
    );
    switch (adoption) {
      case CachedValuesAdoption.adopt:
        _serveCachedValues(cachedValues);
      case CachedValuesAdoption.liveValuesAlreadyArrived:
      case CachedValuesAdoption.contextMismatch:
        _logger.debug(
          '[ConfigDirectorClient] The values kept on the device were not '
          'adopted: ${adoption.description}',
        );
    }
  }

  void _serveCachedValues(CachedValues cachedValues) {
    _configSet = ConfigSet(
      environmentId: cachedValues.environmentId,
      projectId: cachedValues.projectId,
      configs: cachedValues.configs,
      kind: ConfigSetKind.full,
    );
    _configSetSource = _ConfigSetSource.cachedValues;
    final keys = cachedValues.configs.keys.toList(growable: false);

    _emit(_cachedValuesLoaded, const CachedValuesLoadedEvent());
    _emit(_configsUpdated, ConfigsUpdatedEvent(keys));
    _reevaluateWatchers(keys);
    _logger.debug(
      '[ConfigDirectorClient] Serving the values kept on the device until '
      'live values arrive: $keys',
    );
  }

  void _adoptContext(ConfigDirectorContext? context) {
    _currentContext = context;
    unawaited(_telemetry.updateContext(context));
    _emit(_contextUpdated, ContextUpdatedEvent(context));
  }

  static Future<void> _fillInAppInfo(
    TransportOptions transportOptions, {
    required ConfigDirectorMetaContext? provided,
    required AppInfoResolver resolver,
    required Duration timeout,
    required ConfigDirectorLogger logger,
  }) async {
    var appName = provided?.appName;
    var appVersion = provided?.appVersion;

    if (appName == null || appVersion == null) {
      try {
        final detected = await resolver().timeout(timeout);
        appName ??= detected.appName;
        appVersion ??= detected.appVersion;
      } on Object catch (error, stackTrace) {
        logger.debug(
          '[ConfigDirectorClient] Failed to read the app name and version from the platform',
          error,
          stackTrace,
        );
      }

      final metaContext = transportOptions.metaContext;
      transportOptions.metaContext = metaContext.withMetadata(
        ConfigDirectorMetaContext(appName: appName, appVersion: appVersion),
      );
    }

    final missing = [
      if (appName == null) 'name',
      if (appVersion == null) 'version',
    ];
    if (missing.isNotEmpty) {
      final pronoun = missing.length == 1 ? 'it' : 'them';
      logger.info(
        '[ConfigDirectorClient] The ConfigDirector SDK could not find an app '
        '${missing.join(' and ')}, so targeting rules that use $pronoun will '
        'not match. Provide $pronoun through '
        'ConfigDirectorClientOptions.metadata.',
      );
    }
  }

  void _applyConfigSet(ConfigSet configSet) {
    final keys = configSet.configs.keys.toList(growable: false);
    final current = _configSet;
    final isFull = current == null || configSet.kind == ConfigSetKind.full;
    final removedKeys = current == null || !isFull
        ? const <String>[]
        : current.configs.keys
              .where((key) => !configSet.configs.containsKey(key))
              .toList(growable: false);
    final merged = isFull ? configSet : current.mergedWith(configSet);
    _configSet = merged;
    _configSetSource = _ConfigSetSource.livePayload;
    _cachedValuesStore?.replace(_requestedContext, merged);

    _markReady();
    _emit(_configsUpdated, ConfigsUpdatedEvent(keys, removedKeys: removedKeys));
    _reevaluateWatchers(isFull ? _watchers.keys.toList(growable: false) : keys);

    _logger.debug(
      '[ConfigDirectorClient] ConfigSet updated from server: $keys, '
      'removed: $removedKeys',
    );
  }

  void _reevaluateWatchers(List<String> keys) {
    for (final key in keys) {
      for (final watcher in _watchers[key] ?? const <_ConfigWatcher>[]) {
        watcher.reevaluate();
      }
    }
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

  ConfigEvaluation _evaluate<T extends Object>(
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
      final evaluation = ConfigEvaluation(
        key: configKey,
        value: defaultValue,
        isDefaultValue: true,
        reason: reason,
        context: _currentContext,
      );
      _emit(_configEvaluated, ConfigEvaluatedEvent(evaluation));
      return evaluation;
    }

    final result = parseConfigValue(configState, defaultValue);
    final reason = _servedReason(result.reason);
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
        evaluationReason: reason,
      ),
    );
    final evaluation = ConfigEvaluation(
      key: configKey,
      value: result.value,
      valueId: result.valueId,
      isDefaultValue: result.usedDefault,
      reason: reason,
      context: _currentContext,
    );
    _emit(_configEvaluated, ConfigEvaluatedEvent(evaluation));
    _logger.debug(
      "[ConfigDirectorClient] Evaluated '$configKey' to '${result.value}'",
    );
    return evaluation;
  }

  EvaluationReason _servedReason(EvaluationReason reason) =>
      _configSetSource == _ConfigSetSource.cachedValues &&
          reason == EvaluationReason.foundMatch
      ? EvaluationReason.cached
      : reason;

  void _followAppLifecycle(AppLifecycleState state) {
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
    LiveConnectionMode mode,
    TransportOptions options,
  ) => switch (mode) {
    LiveConnectionMode.streaming => StreamingTransport(options),
    LiveConnectionMode.polling => PollingTransport(options),
  };

  static Duration _exponentialRetryDelay(int attempt) =>
      Duration(seconds: pow(2, min(attempt, _maxBackoffExponent)).toInt());

  void _validateDefaultValue<T extends Object>(T defaultValue) {
    if (defaultValue is Function) {
      throw const ConfigDirectorValidationException(
        'Invalid default value. The default value for a config cannot be a function.',
      );
    }
  }
}
