import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_openfeature_flutter_provider/src/config_director_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';

import 'support/fake_client.dart';

void main() {
  late OpenFeatureAPI api;
  late FakeConfigDirectorClient configDirectorClient;
  late ConfigDirectorProvider provider;

  Future<void> deliverClientEvents() => Future<void>.delayed(Duration.zero);

  List<ProviderEventDetails> record(ProviderEventType type) {
    final received = <ProviderEventDetails>[];
    api.addHandler(type, received.add);
    return received;
  }

  setUp(() {
    api = createIsolatedOpenFeatureAPI(
      lifecycleTimeout: const Duration(seconds: 2),
    );
    configDirectorClient = FakeConfigDirectorClient(
      values: {
        'dark-mode': true,
        'greeting': 'hello',
        'max-items': 7,
        'ratio': 1.5,
        'theme': <String, Object?>{'accent': 'teal'},
      },
    );
    provider = providerForClient(configDirectorClient);
  });

  tearDown(() => api.shutdown());

  test('becomes the ready provider of OpenFeature clients', () async {
    await api.setProviderAndWait(provider);

    final client = api.getClient();
    expect(client.providerStatus, ProviderStatus.ready);
    expect(client.providerMetadata.name, 'ConfigDirectorProvider');
  });

  test('initializes against the context set before registration', () async {
    await api.setEvaluationContextAndWait(
      EvaluationContext(targetingKey: 'user-123'),
    );

    await api.setProviderAndWait(provider);

    expect(configDirectorClient.initializeCalls, [
      const ConfigDirectorContext(id: 'user-123'),
    ]);
  });

  test('evaluates every flag type through an OpenFeature client', () async {
    await api.setProviderAndWait(provider);
    final client = api.getClient();

    expect(client.getBooleanValue('dark-mode', false), isTrue);
    expect(client.getStringValue('greeting', 'default'), 'hello');
    expect(client.getIntegerValue('max-items', 0), 7);
    expect(client.getDoubleValue('ratio', 0.5), 1.5);
    expect(client.getStructureValue('theme', const {}), {'accent': 'teal'});
    expect(client.getStringValue('missing', 'default'), 'default');
  });

  test('exposes resolution details through an OpenFeature client', () async {
    await api.setProviderAndWait(provider);
    final client = api.getClient();

    final served = client.getBooleanDetails('dark-mode', false);
    expect(served.value, isTrue);
    expect(served.variant, 'value-id-dark-mode');
    expect(served.reason, 'TARGETING_MATCH');
    expect(served.errorCode, isNull);

    final unknown = client.getStringDetails('missing', 'default');
    expect(unknown.value, 'default');
    expect(unknown.errorCode, ErrorCode.flagNotFound);
    expect(unknown.reason, 'ERROR');
  });

  test('notifies ready handlers once', () async {
    final ready = record(ProviderEventType.ready);

    await api.setProviderAndWait(provider);
    await deliverClientEvents();

    expect(ready, hasLength(1));
  });

  test('fails registration when the client does not become ready', () async {
    configDirectorClient.connectionSucceeds = false;
    final errors = record(ProviderEventType.error);

    await expectLater(
      api.setProviderAndWait(provider),
      throwsA(isA<OpenFeatureException>()),
    );

    expect(api.getClient().providerStatus, ProviderStatus.error);
    expect(errors, hasLength(1));
  });

  test(
    'recovers once the client connects after a failed registration',
    () async {
      configDirectorClient.connectionSucceeds = false;
      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(isA<OpenFeatureException>()),
      );
      final ready = record(ProviderEventType.ready);

      configDirectorClient.becomeReady(ClientConnectAction.initialization);
      await deliverClientEvents();

      expect(api.getClient().providerStatus, ProviderStatus.ready);
      expect(ready, hasLength(1));
      expect(api.getClient().getBooleanValue('dark-mode', false), isTrue);
    },
  );

  test('reconciles a context change', () async {
    await api.setProviderAndWait(provider);
    final reconciling = record(ProviderEventType.reconciling);
    final contextChanged = record(ProviderEventType.contextChanged);

    await api.setEvaluationContextAndWait(
      EvaluationContext(
        targetingKey: 'user-456',
        attributes: {
          'traits': {'plan': 'pro'},
        },
      ),
    );

    expect(configDirectorClient.updateContextCalls, [
      const ConfigDirectorContext(id: 'user-456', traits: {'plan': 'pro'}),
    ]);
    expect(reconciling, hasLength(1));
    expect(contextChanged, hasLength(1));
    expect(api.getClient().providerStatus, ProviderStatus.ready);
  });

  test('fails a context change the client does not become ready for', () async {
    await api.setProviderAndWait(provider);
    configDirectorClient.connectionSucceeds = false;

    await expectLater(
      api.setEvaluationContextAndWait(
        EvaluationContext(targetingKey: 'user-456'),
      ),
      throwsA(isA<OpenFeatureException>()),
    );
    expect(api.getClient().providerStatus, ProviderStatus.error);

    configDirectorClient.becomeReady(ClientConnectAction.contextUpdate);
    await deliverClientEvents();

    expect(api.getClient().providerStatus, ProviderStatus.ready);
  });

  test(
    'notifies configuration change handlers with the changed flags',
    () async {
      await api.setProviderAndWait(provider);
      final changes = record(ProviderEventType.configurationChanged);

      configDirectorClient.receiveConfigs(['dark-mode']);
      await deliverClientEvents();

      expect(changes.single.flagsChanged, ['dark-mode']);
    },
  );

  test('disposes of the client when OpenFeature shuts down', () async {
    await api.setProviderAndWait(provider);

    await api.shutdown();

    expect(configDirectorClient.disposed, isTrue);
  });
}
