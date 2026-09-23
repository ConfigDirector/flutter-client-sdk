import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_openfeature_flutter_provider/src/config_director_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

import 'support/fake_client.dart';

void main() {
  late FakeConfigDirectorClient client;
  late ConfigDirectorProvider provider;
  late List<ProviderEvent> events;

  List<ProviderEventType> eventTypes() =>
      events.map((event) => event.type).toList();

  Future<void> deliverClientEvents() => Future<void>.delayed(Duration.zero);

  setUp(() {
    client = FakeConfigDirectorClient();
    provider = providerForClient(client);
    events = [];
    provider.events.listen(events.add);
  });

  tearDown(() => provider.shutdown());

  test('identifies itself as the ConfigDirector provider', () {
    expect(provider.metadata.name, 'ConfigDirectorProvider');
  });

  test('rejects an invalid SDK key on creation', () {
    expect(
      () => ConfigDirectorProvider(clientSdkKey: ''),
      throwsA(isA<ConfigDirectorValidationException>()),
    );
  });

  group('initialize', () {
    test('initializes the client with the mapped context', () async {
      await provider.initialize(EvaluationContext(targetingKey: 'user-123'));

      expect(client.initializeCalls, [
        const ConfigDirectorContext(id: 'user-123'),
      ]);
    });

    test('reports ready once when the client becomes ready', () async {
      await provider.initialize(EvaluationContext.empty);
      await deliverClientEvents();

      expect(eventTypes(), [ProviderEventType.ready]);
    });

    test('reports ready before it completes', () async {
      List<ProviderEventType>? seenOnCompletion;

      await provider
          .initialize(EvaluationContext.empty)
          .then((_) => seenOnCompletion = eventTypes());

      expect(seenOnCompletion, [ProviderEventType.ready]);
    });

    test('reports an error when the client does not become ready', () async {
      client.connectionSucceeds = false;

      await provider.initialize(EvaluationContext.empty);

      expect(eventTypes(), [ProviderEventType.error]);
      expect(events.single.errorCode, ErrorCode.general);
      expect(events.single.message, contains('initialization'));
    });

    test('reports ready once the client recovers', () async {
      client.connectionSucceeds = false;
      await provider.initialize(EvaluationContext.empty);

      client.becomeReady(ClientConnectAction.initialization);
      await deliverClientEvents();

      expect(eventTypes(), [ProviderEventType.error, ProviderEventType.ready]);
    });
  });

  group('onContextChanged', () {
    setUp(() async {
      await provider.initialize(EvaluationContext.empty);
      await deliverClientEvents();
      events.clear();
    });

    test('updates the client with the mapped new context', () async {
      await provider.onContextChanged(
        EvaluationContext(targetingKey: 'old'),
        EvaluationContext(targetingKey: 'new', attributes: {'name': 'Ada'}),
      );

      expect(client.updateContextCalls, [
        const ConfigDirectorContext(id: 'new', name: 'Ada'),
      ]);
    });

    test('reports reconciling, then the context change', () async {
      await provider.onContextChanged(
        EvaluationContext.empty,
        EvaluationContext(targetingKey: 'new'),
      );
      await deliverClientEvents();

      expect(eventTypes(), [
        ProviderEventType.reconciling,
        ProviderEventType.contextChanged,
      ]);
    });

    test('reports reconciling while the client is still connecting', () async {
      client.connectionGate = Completer<void>();

      final change = provider.onContextChanged(
        EvaluationContext.empty,
        EvaluationContext(targetingKey: 'new'),
      );

      expect(eventTypes(), [ProviderEventType.reconciling]);
      client.connectionGate!.complete();
      await change;
    });

    test('reports an error when the client does not become ready', () async {
      client.connectionSucceeds = false;

      await provider.onContextChanged(
        EvaluationContext.empty,
        EvaluationContext(targetingKey: 'new'),
      );

      expect(eventTypes(), [
        ProviderEventType.reconciling,
        ProviderEventType.error,
      ]);
      expect(events.last.errorCode, ErrorCode.general);
      expect(events.last.message, contains('context'));
    });

    test('reports ready once the client recovers', () async {
      client.connectionSucceeds = false;
      await provider.onContextChanged(
        EvaluationContext.empty,
        EvaluationContext(targetingKey: 'new'),
      );
      events.clear();

      client.becomeReady(ClientConnectAction.contextUpdate);
      await deliverClientEvents();

      expect(eventTypes(), [ProviderEventType.ready]);
    });
  });

  test('stops waiting to recover once a context change succeeds', () async {
    client.connectionSucceeds = false;
    await provider.initialize(EvaluationContext.empty);
    client.connectionSucceeds = true;
    events.clear();

    await provider.onContextChanged(
      EvaluationContext.empty,
      EvaluationContext(targetingKey: 'new'),
    );
    await deliverClientEvents();

    expect(eventTypes(), [
      ProviderEventType.reconciling,
      ProviderEventType.contextChanged,
    ]);
  });

  test('does not report ready when the client reconnects on its own', () async {
    await provider.initialize(EvaluationContext.empty);
    await deliverClientEvents();
    events.clear();

    client.becomeReady(ClientConnectAction.networkResume);
    await deliverClientEvents();

    expect(events, isEmpty);
  });

  test('reports a configuration change with the updated keys', () async {
    client.receiveConfigs(['dark-mode', 'max-items']);
    await deliverClientEvents();

    expect(eventTypes(), [ProviderEventType.configurationChanged]);
    expect(events.single.flagsChanged, ['dark-mode', 'max-items']);
  });

  group('resolution', () {
    setUp(() {
      client.values.addAll({
        'a-bool': true,
        'a-string': 'hello',
        'an-int': 7,
        'a-double': 1.5,
        'a-structure': <String, Object?>{
          'nested': {'enabled': true},
        },
      });
    });

    test('resolves a boolean', () {
      final details = provider.resolveBooleanValue(
        'a-bool',
        false,
        EvaluationContext.empty,
      );

      expect(details.value, isTrue);
      expect(details.errorCode, isNull);
    });

    test('resolves a string', () {
      expect(
        provider
            .resolveStringValue('a-string', 'default', EvaluationContext.empty)
            .value,
        'hello',
      );
    });

    test('resolves an integer', () {
      expect(
        provider
            .resolveIntegerValue('an-int', 0, EvaluationContext.empty)
            .value,
        7,
      );
    });

    test('resolves a double', () {
      expect(
        provider
            .resolveDoubleValue('a-double', 0.5, EvaluationContext.empty)
            .value,
        1.5,
      );
    });

    test('resolves a structure', () {
      expect(
        provider
            .resolveStructureValue(
              'a-structure',
              const {},
              EvaluationContext.empty,
            )
            .value,
        {
          'nested': {'enabled': true},
        },
      );
    });

    test('carries the served value id as the variant', () {
      final details = provider.resolveStringValue(
        'a-string',
        'default',
        EvaluationContext.empty,
      );

      expect(details.variant, 'value-id-a-string');
      expect(details.reason, 'TARGETING_MATCH');
      expect(details.errorCode, isNull);
    });

    test('resolves a config without a value to the default', () {
      client.keysWithoutValue.add('unset');

      final details = provider.resolveIntegerValue(
        'unset',
        3,
        EvaluationContext.empty,
      );

      expect(details.value, 3);
      expect(details.reason, 'DEFAULT');
      expect(details.variant, isNull);
      expect(details.errorCode, isNull);
    });

    test('reports an unknown key once the client is ready', () async {
      await provider.initialize(EvaluationContext.empty);

      final details = provider.resolveStringValue(
        'missing',
        'default',
        EvaluationContext.empty,
      );

      expect(details.value, 'default');
      expect(details.errorCode, ErrorCode.flagNotFound);
      expect(details.errorMessage, contains("'missing'"));
      expect(details.reason, 'ERROR');
    });

    test('reports the provider not being ready', () {
      final details = provider.resolveStringValue(
        'missing',
        'default',
        EvaluationContext.empty,
      );

      expect(details.value, 'default');
      expect(details.errorCode, ErrorCode.providerNotReady);
      expect(details.reason, 'ERROR');
    });

    test('reports a value that cannot be read as the requested type', () {
      final details = provider.resolveIntegerValue(
        'a-string',
        3,
        EvaluationContext.empty,
      );

      expect(details.value, 3);
      expect(details.errorCode, ErrorCode.typeMismatch);
      expect(details.errorMessage, contains('type-mismatch'));
      expect(details.reason, 'ERROR');
    });

    test('resolves to the default value when the client has no value', () {
      expect(
        provider
            .resolveStringValue('missing', 'default', EvaluationContext.empty)
            .value,
        'default',
      );
    });

    test('resolves to the default value when the type does not match', () {
      expect(
        provider
            .resolveIntegerValue('a-string', 3, EvaluationContext.empty)
            .value,
        3,
      );
    });
  });

  group('shutdown', () {
    test('disposes of the client', () async {
      await provider.shutdown();

      expect(client.disposed, isTrue);
    });

    test('closes the event stream', () async {
      final done = Completer<void>();
      provider.events.listen(null, onDone: done.complete);

      await provider.shutdown();

      expect(done.isCompleted, isTrue);
    });

    test('is safe to call twice', () async {
      await provider.shutdown();

      await expectLater(provider.shutdown(), completes);
    });

    test('lets an initialization in flight finish quietly', () async {
      client.connectionGate = Completer<void>();
      final initialization = provider.initialize(EvaluationContext.empty);

      await provider.shutdown();

      await expectLater(initialization, completes);
      expect(events, isEmpty);
    });
  });
}
