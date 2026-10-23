import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/wrapper.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

import 'constants.dart' as constants;
import 'context_mapper.dart';
import 'resolution.dart';

/// An [OpenFeature](https://openfeature.dev) provider that resolves flags with
/// the ConfigDirector Flutter client SDK.
///
/// Register one instance with the OpenFeature Dart client SDK
/// (`openfeature_dart_client_sdk`) during application startup:
///
/// ```dart
/// await OpenFeatureAPI.instance.setEvaluationContextAndWait(
///   EvaluationContext(targetingKey: 'user-123'),
/// );
/// await OpenFeatureAPI.instance.setProviderAndWait(
///   ConfigDirectorProvider(clientSdkKey: 'YOUR-CLIENT-SDK-KEY'),
/// );
///
/// final client = OpenFeatureAPI.instance.getClient();
/// final darkMode = client.getBooleanValue('dark-mode', false);
/// ```
///
/// The provider connects to ConfigDirector when it is registered and evaluates
/// every flag from the config state it holds locally, so resolving a flag never
/// waits on the network.
///
/// ## Evaluation context
///
/// The OpenFeature evaluation context is sent to ConfigDirector as the context,
/// and targeting rules are evaluated against it:
///
/// | OpenFeature                        | ConfigDirector |
/// | ---------------------------------- | -------------- |
/// | `targetingKey`, or else `id`       | `id`           |
/// | `kind`                             | `kind`         |
/// | `name`                             | `name`         |
/// | `traits`, a structure              | `traits`       |
/// | `anonymous`, a boolean             | `anonymous`    |
///
/// Any other attribute is ignored. Put the values targeting rules depend on
/// inside `traits`; a `kind` inside `traits` is an ordinary trait. Leaving
/// `kind` out means `user`, and a context with an invalid `kind` is ignored as
/// a whole: the SDK logs an error and flags resolve as if no context was set.
/// The context handed to an individual resolution is ignored as well: flags
/// are evaluated against the context most recently set.
///
/// ## Resolution details
///
/// A flag ConfigDirector served resolves with the reason `TARGETING_MATCH` and
/// the served value's id as its variant; one served from the values kept on
/// the device, before live values arrive, resolves the same way with the
/// reason `CACHED`. One the config has no value for resolves to the default
/// with the reason `DEFAULT`. Everything else is an
/// error carrying the default: `flagNotFound` for an unknown key,
/// `providerNotReady` before config state has arrived, and `typeMismatch` for
/// a value that cannot be read as the requested type.
///
/// ## Provider status
///
/// The provider is ready once ConfigDirector has delivered config state. When
/// that does not happen within [ConnectionOptions.timeout], registration and
/// context changes fail with an `OpenFeatureException` and the provider reports
/// an error. The underlying client keeps trying to connect, and the provider
/// reports ready as soon as it succeeds. Until then flags resolve to the config
/// state received earlier, or to their default values when there is none.
///
/// The underlying client keeps the last values it received on the device and
/// serves them on the next launch of the same context until live values
/// arrive; see [CachingOptions]. The provider reports stale while it serves
/// them: from the moment they are loaded, and again right after the error it
/// reports when registration or a context change times out, once the
/// OpenFeature SDK has recorded that error, until live values arrive and it
/// reports ready.
///
/// A configuration-changed event is emitted every time config state arrives,
/// carrying the keys of the configs in the update followed by the keys of
/// configs a full update removed.
///
/// ## Offline mode
///
/// With [ConnectionMode.offline] the provider never connects and resolves
/// every flag from [ConnectionOptions.values], the same value for every
/// context, with the reason `TARGETING_MATCH`; a config without a value there
/// resolves to the default with the error code `flagNotFound`. Registration
/// completes at once with the provider ready. When the values cannot be
/// loaded, `setProviderAndWait` throws the
/// [ConfigDirectorInitializationException] the underlying client throws, and
/// the provider is not registered.
///
/// An instance serves a single registration. After OpenFeature shuts it down,
/// create a new one.
final class ConfigDirectorProvider
    implements
        FeatureProvider,
        InitializableProvider,
        ContextReconciliationProvider,
        ShutdownProvider,
        ProviderEventSource {
  /// Creates a provider for [clientSdkKey], the client SDK key from the
  /// ConfigDirector dashboard.
  ///
  /// [options] configures the underlying ConfigDirector client: application
  /// metadata, the connection mode, polling interval, and timeout, the values
  /// kept on the device, and logging.
  ///
  /// [clientSdkKey] may be left out in [ConnectionMode.offline], which never
  /// connects and serves the values given in [ConnectionOptions.values]:
  ///
  /// ```dart
  /// final provider = ConfigDirectorProvider(
  ///   options: const ConfigDirectorClientOptions(
  ///     connection: ConnectionOptions(
  ///       mode: ConnectionMode.offline,
  ///       values: {'new-checkout': true},
  ///     ),
  ///   ),
  /// );
  /// ```
  ///
  /// In every other mode, a missing or blank [clientSdkKey] throws a
  /// [ConfigDirectorValidationException].
  ConfigDirectorProvider({
    String? clientSdkKey,
    ConfigDirectorClientOptions? options,
  }) : this._(
         createWrapperClient(
           clientSdkKey: clientSdkKey,
           identity: SdkIdentity.openFeatureProvider(constants.sdkVersion),
           options: options,
         ),
       );

  ConfigDirectorProvider._(ConfigDirectorClient client) : _client = client {
    _clientReadySubscription = client.onClientReady.listen(_handleClientReady);
    _configsUpdatedSubscription = client.onConfigsUpdated.listen(
      _handleConfigsUpdated,
    );
    _cachedValuesLoadedSubscription = client.onCachedValuesLoaded.listen(
      _handleCachedValuesLoaded,
    );
  }

  final ConfigDirectorClient _client;
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);

  late final StreamSubscription<ClientReadyEvent> _clientReadySubscription;
  late final StreamSubscription<ConfigsUpdatedEvent>
  _configsUpdatedSubscription;
  late final StreamSubscription<CachedValuesLoadedEvent>
  _cachedValuesLoadedSubscription;

  bool _awaitingRecovery = false;
  bool _servingCachedValues = false;

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'ConfigDirectorProvider');

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    _awaitingRecovery = false;
    await _client.initialize(mapEvaluationContext(context));
    _reportOutcome(
      success: ProviderEventType.ready,
      failureMessage:
          'ConfigDirector did not become ready during initialization. Flags '
          'resolve to their default values until the connection succeeds.',
    );
  }

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    _awaitingRecovery = false;
    _emit(ProviderEvent(type: ProviderEventType.reconciling));
    await _client.updateContext(mapEvaluationContext(newContext));
    _reportOutcome(
      success: ProviderEventType.contextChanged,
      failureMessage:
          'ConfigDirector did not become ready after the context changed. '
          'Flags resolve against the previous context until the connection '
          'succeeds.',
    );
  }

  @override
  Future<void> shutdown() async {
    await _clientReadySubscription.cancel();
    await _configsUpdatedSubscription.cancel();
    await _cachedValuesLoadedSubscription.cancel();
    _client.dispose();
    await _events.close();
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  ResolutionDetails<T> _resolve<T extends Object>(
    String flagKey,
    T defaultValue,
  ) {
    final evaluation = _client.evaluate<T>(flagKey, defaultValue);
    return resolutionOf(evaluation, evaluation.value as T);
  }

  void _reportOutcome({
    required ProviderEventType success,
    required String failureMessage,
  }) {
    if (_client.isReady) {
      _emit(ProviderEvent(type: success));
      return;
    }

    _awaitingRecovery = true;
    _emit(
      ProviderEvent(
        type: ProviderEventType.error,
        errorCode: ErrorCode.general,
        message: failureMessage,
      ),
    );
    Timer.run(_reportStatusOnceTheOutcomeIsRecorded);
  }

  void _reportStatusOnceTheOutcomeIsRecorded() {
    switch (_statusReportFor(
      servingCachedValues: _servingCachedValues,
      awaitingRecovery: _awaitingRecovery,
    )) {
      case _StatusReport.stale:
        _emit(ProviderEvent(type: ProviderEventType.stale));
      case _StatusReport.asRecorded:
        return;
    }
  }

  void _handleCachedValuesLoaded(CachedValuesLoadedEvent event) {
    _servingCachedValues = true;
    _emit(ProviderEvent(type: ProviderEventType.stale));
  }

  void _handleClientReady(ClientReadyEvent event) {
    _servingCachedValues = false;
    if (!_awaitingRecovery) {
      return;
    }

    _awaitingRecovery = false;
    _emit(ProviderEvent(type: ProviderEventType.ready));
  }

  void _handleConfigsUpdated(ConfigsUpdatedEvent event) {
    _emit(
      ProviderEvent(
        type: ProviderEventType.configurationChanged,
        flagsChanged: [...event.keys, ...event.removedKeys],
      ),
    );
  }

  void _emit(ProviderEvent event) {
    if (_events.isClosed) {
      return;
    }

    _events.add(event);
  }
}

ConfigDirectorProvider providerForClient(ConfigDirectorClient client) =>
    ConfigDirectorProvider._(client);

enum _StatusReport { stale, asRecorded }

_StatusReport _statusReportFor({
  required bool servingCachedValues,
  required bool awaitingRecovery,
}) => servingCachedValues && awaitingRecovery
    ? _StatusReport.stale
    : _StatusReport.asRecorded;
