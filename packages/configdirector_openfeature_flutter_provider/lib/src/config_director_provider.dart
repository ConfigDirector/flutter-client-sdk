import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

import 'context_mapper.dart';

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
/// The OpenFeature evaluation context is sent to ConfigDirector as the user's
/// context, and targeting rules are evaluated against it:
///
/// | OpenFeature                        | ConfigDirector |
/// | ---------------------------------- | -------------- |
/// | `targetingKey`, or else `id`       | `id`           |
/// | `name`                             | `name`         |
/// | `traits`, a structure              | `traits`       |
/// | `anonymous`, a boolean             | `anonymous`    |
///
/// Any other attribute is ignored. Put the values targeting rules depend on
/// inside `traits`.
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
/// A configuration-changed event is emitted every time config state arrives,
/// carrying the keys of the configs in the update.
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
  /// metadata, the connection mode and timeout, and logging.
  ConfigDirectorProvider({
    required String clientSdkKey,
    ConfigDirectorClientOptions? options,
  }) : this.withClient(
         ConfigDirectorClient(clientSdkKey: clientSdkKey, options: options),
       );

  /// Creates a provider that resolves flags with [client].
  ///
  /// Use this to keep a reference to the client, for instance to `watch` a
  /// config alongside OpenFeature. The provider owns [client] from here on: it
  /// initializes it, updates its context, and disposes of it on shutdown, so
  /// do not call `initialize`, `updateContext` or `dispose` on it yourself.
  ConfigDirectorProvider.withClient(ConfigDirectorClient client)
    : _client = client {
    _clientReadySubscription = client.onClientReady.listen(_handleClientReady);
    _configsUpdatedSubscription = client.onConfigsUpdated.listen(
      _handleConfigsUpdated,
    );
  }

  final ConfigDirectorClient _client;
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);

  late final StreamSubscription<ClientReadyEvent> _clientReadySubscription;
  late final StreamSubscription<ConfigsUpdatedEvent>
  _configsUpdatedSubscription;

  bool _awaitingRecovery = false;

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
  ) => ResolutionDetails<T>(value: _client.getValue<T>(flagKey, defaultValue));

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
  }

  void _handleClientReady(ClientReadyEvent event) {
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
        flagsChanged: event.keys,
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
