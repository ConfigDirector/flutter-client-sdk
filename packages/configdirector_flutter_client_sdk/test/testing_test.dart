import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const ConfigDirectorContext _userA = ConfigDirectorContext(id: 'user-a');
const ConfigDirectorContext _userB = ConfigDirectorContext(id: 'user-b');
const Duration _shortTimeout = Duration(milliseconds: 50);

void main() {
  late RecordingLogger logger;

  setUp(() => logger = RecordingLogger());

  TestClient create({
    Map<String, Object?> values = const {},
    Duration? timeout,
    ConfigDirectorLogger? logger,
  }) {
    final testClient = createTestClient(
      values: values,
      timeout: timeout,
      logger: logger,
    );
    addTearDown(testClient.client.dispose);
    return testClient;
  }

  group('values', () {
    test('S1 reads every seeded value with a matching default', () async {
      final testClient = create(
        values: {
          'flag': true,
          'count': 20,
          'ratio': 2.5,
          'name': 'Ada',
          'settings': {'theme': 'dark', 'limit': 3},
          'tags': ['x', 'y'],
        },
      );
      final client = testClient.client;

      await client.initialize();

      expect(client.isReady, isTrue);
      expect(client.getValue('flag', false), isTrue);
      expect(client.getValue('count', 0), 20);
      expect(client.getValue('ratio', 0.0), 2.5);
      expect(client.getValue('name', ''), 'Ada');
      expect(client.getValue<Map<String, Object?>>('settings', const {}), {
        'theme': 'dark',
        'limit': 3,
      });
      expect(client.getValue<List<Object?>>('tags', const []), ['x', 'y']);
      expect(
        client.evaluate('flag', false).reason,
        EvaluationReason.foundMatch,
      );
    });

    test('S2 a boolean read as a string is a type mismatch', () async {
      final testClient = create(values: {'flag': true});
      await testClient.client.initialize();

      final evaluation = testClient.client.evaluate('flag', 'fallback');

      expect(evaluation.value, 'fallback');
      expect(evaluation.isDefaultValue, isTrue);
      expect(evaluation.reason, EvaluationReason.typeMismatch);
    });

    test('S3 setValue on a connected client changes the next read', () async {
      final testClient = create(values: {'flag': true});
      await testClient.client.initialize();

      testClient.setValue('flag', false);
      await pumpEventQueue();

      expect(testClient.client.getValue('flag', true), isFalse);
    });

    test('S8 setValue before initialize is delivered by initialize', () async {
      final testClient = create();
      testClient.setValue('count', 7);

      await testClient.client.initialize();

      expect(testClient.client.getValue('count', 0), 7);
    });

    test('S6 removeValue on a connected client reads as the default', () async {
      final testClient = create(values: {'flag': true});
      await testClient.client.initialize();

      testClient.removeValue('flag');
      await pumpEventQueue();

      final evaluation = testClient.client.evaluate('flag', false);
      expect(evaluation.value, isFalse);
      expect(evaluation.reason, EvaluationReason.configStateMissing);
    });

    test('S24 removeValue before initialize reads as the default', () async {
      final testClient = create(values: {'flag': true});
      testClient.removeValue('flag');

      await testClient.client.initialize();

      final evaluation = testClient.client.evaluate('flag', false);
      expect(evaluation.value, isFalse);
      expect(evaluation.reason, EvaluationReason.configStateMissing);
    });

    test('S32 replaceValues serves exactly the new values', () async {
      final testClient = create(values: {'a': 1, 'b': 2});
      final client = testClient.client;
      final bValues = <int>[];
      client.watch('b', 0).listen(bValues.add);
      await client.initialize();
      await pumpEventQueue();

      testClient.replaceValues({'a': 10, 'c': 30});
      await pumpEventQueue();

      expect(client.getValue('a', 0), 10);
      expect(client.getValue('c', 0), 30);
      final b = client.evaluate('b', 0);
      expect(b.value, 0);
      expect(b.reason, EvaluationReason.configStateMissing);
      expect(bValues, [0, 2, 0]);
    });

    test('S15 two test clients never share values', () async {
      final first = create(values: {'flag': true});
      final second = create(values: {'flag': false, 'only-second': 1});
      await first.client.initialize();
      await second.client.initialize();

      first.setValue('flag', false);
      second.setValue('only-second', 2);
      await pumpEventQueue();

      expect(first.client.getValue('flag', true), isFalse);
      expect(second.client.getValue('flag', true), isFalse);
      expect(
        first.client.evaluate('only-second', 0).reason,
        EvaluationReason.configStateMissing,
      );
      expect(second.client.getValue('only-second', 0), 2);
    });

    test('serves the same value to every context', () async {
      final testClient = create(values: {'flag': true});
      await testClient.client.initialize(_userA);
      expect(testClient.client.getValue('flag', false), isTrue);

      await testClient.client.updateContext(_userB);

      expect(testClient.client.getValue('flag', false), isTrue);
      expect(testClient.client.context, _userB);
    });

    test('a String spelling JSON is a string config', () async {
      final testClient = create(values: {'doc': '{"a":1}'});
      await testClient.client.initialize();

      expect(testClient.client.getValue('doc', ''), '{"a":1}');
      expect(
        testClient.client
            .evaluate<Map<String, Object?>>('doc', const {})
            .reason,
        EvaluationReason.typeMismatch,
      );
    });

    test('an empty string serves the default with value missing', () async {
      final testClient = create(values: {'name': ''});
      await testClient.client.initialize();

      final evaluation = testClient.client.evaluate('name', 'fallback');
      expect(evaluation.value, 'fallback');
      expect(evaluation.reason, EvaluationReason.valueMissing);
    });

    test(
      'a float read with an int default is truncated, as in production',
      () async {
        final testClient = create(values: {'ratio': 2.5});
        await testClient.client.initialize();

        expect(testClient.client.getValue('ratio', 1), 2);
      },
    );

    test('rejects invalid values without changing anything', () async {
      final testClient = create(values: {'flag': true});
      await testClient.client.initialize();

      expect(
        () => testClient.setValue('flag', null),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
      expect(
        () => testClient.setValue('', true),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
      expect(
        () => testClient.setValue('when', DateTime(2026)),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
      expect(
        () => testClient.replaceValues({'flag': false, 'ratio': double.nan}),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
      expect(
        () => createTestClient(values: {'k': null}),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
      await pumpEventQueue();

      expect(testClient.client.getValue('flag', false), isTrue);
    });
  });

  group('events and watchers', () {
    test('S4 setValue fires the watcher and lists the key', () async {
      final testClient = create(values: {'dark-mode': false});
      final client = testClient.client;
      final seen = <bool>[];
      final updates = <ConfigsUpdatedEvent>[];
      client.watch('dark-mode', false).listen(seen.add);
      client.onConfigsUpdated.listen(updates.add);
      await client.initialize();
      await pumpEventQueue();

      testClient.setValue('dark-mode', true);
      await pumpEventQueue();

      expect(seen, [false, true]);
      expect(updates.last.keys, ['dark-mode']);
      expect(updates.last.removedKeys, isEmpty);
    });

    test('S5 setValue of another key leaves a watcher alone', () async {
      final testClient = create(values: {'a': 1, 'b': 2});
      final client = testClient.client;
      final seen = <int>[];
      client.watch('a', 0).listen(seen.add);
      await client.initialize();
      await pumpEventQueue();
      final before = seen.length;

      testClient.setValue('b', 3);
      await pumpEventQueue();

      expect(seen.length, before);
    });

    test('S7 removeValue fires the watcher with the default and reports the '
        'key as removed', () async {
      final testClient = create(values: {'dark-mode': true, 'other': 1});
      final client = testClient.client;
      final seen = <bool>[];
      final updates = <ConfigsUpdatedEvent>[];
      client.watch('dark-mode', false).listen(seen.add);
      client.onConfigsUpdated.listen(updates.add);
      await client.initialize();
      await pumpEventQueue();

      testClient.removeValue('dark-mode');
      await pumpEventQueue();

      expect(seen, [false, true, false]);
      expect(updates.last.keys, ['other']);
      expect(updates.last.removedKeys, ['dark-mode']);
    });

    test('S39 initialize emits context updated, client ready, then configs '
        'updated', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      final order = <String>[];
      client.onContextUpdated.listen((_) => order.add('contextUpdated'));
      client.onClientReady.listen(
        (event) => order.add('clientReady:${event.action.name}'),
      );
      client.onConfigsUpdated.listen((_) => order.add('configsUpdated'));

      await client.initialize(_userA);
      await pumpEventQueue();

      expect(order, [
        'contextUpdated',
        'clientReady:initialization',
        'configsUpdated',
      ]);
    });

    test('S41 an operation called from a watcher is delivered after the outer '
        'update', () async {
      final testClient = create(values: {'a': 1});
      final client = testClient.client;
      var readyCount = 0;
      final updates = <List<String>>[];
      client.onClientReady.listen((_) => readyCount++);
      client.onConfigsUpdated.listen((event) => updates.add(event.keys));
      await client.initialize();
      client
          .watch('a', 0)
          .listen((value) => testClient.setValue('b', value * 2));
      await pumpEventQueue();
      expect(client.getValue('b', 0), 2);

      testClient.setValue('a', 5);
      await pumpEventQueue();

      expect(client.getValue('a', 0), 5);
      expect(client.getValue('b', 0), 10);
      expect(readyCount, 1);
      expect(updates, [
        ['a'],
        ['b'],
        ['a'],
        ['b'],
      ]);
    });

    test('a throwing watcher surfaces as an uncaught error', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      final errors = <Object>[];

      await runZonedGuarded(() async {
        client.watch('flag', false).listen((_) => throw StateError('boom'));
        await client.initialize();
        await pumpEventQueue();
      }, (error, stackTrace) => errors.add(error));

      expect(errors, isNotEmpty);
      expect(errors, everyElement(isA<StateError>()));
      expect(client.isReady, isTrue);
    });
  });

  group('initialization', () {
    test('S9 a held initialize stays pending until completed', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      final readyEvents = <ClientReadyEvent>[];
      client.onClientReady.listen(readyEvents.add);
      testClient.holdInitialization();

      final initialization = client.initialize();
      await pumpEventQueue();
      expect(client.isReady, isFalse);
      expect(client.isInitializing, isTrue);
      expect(client.getValue('flag', false), isFalse);

      testClient.completeInitialization();
      await initialization;
      await pumpEventQueue();

      expect(client.isReady, isTrue);
      expect(client.getValue('flag', false), isTrue);
      expect(readyEvents.single.action, ClientConnectAction.initialization);
    });

    test('S10 a value set while held is delivered on completion', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      testClient.holdInitialization();

      final initialization = client.initialize();
      await pumpEventQueue();
      testClient.setValue('flag', false);
      testClient.setValue('count', 3);
      testClient.completeInitialization();
      await initialization;

      expect(client.getValue('flag', true), isFalse);
      expect(client.getValue('count', 0), 3);
    });

    test('S11 a held initialize times out not ready and the next one is '
        'served', () async {
      final testClient = create(
        values: {'flag': true},
        timeout: _shortTimeout,
        logger: logger,
      );
      final client = testClient.client;
      final readyEvents = <ClientReadyEvent>[];
      client.onClientReady.listen(readyEvents.add);
      testClient.holdInitialization();

      await client.initialize();
      expect(client.isReady, isFalse);
      expect(
        logger.warnings,
        contains(contains('Timed out waiting for initialization')),
      );

      testClient.completeInitialization();
      await pumpEventQueue();
      expect(client.isReady, isFalse);
      expect(readyEvents, isEmpty);

      await client.initialize();
      await pumpEventQueue();

      expect(client.isReady, isTrue);
      expect(client.getValue('flag', false), isTrue);
      expect(readyEvents, hasLength(1));
    });

    test('S12 a failed initialize completes promptly and not ready', () async {
      final testClient = create(
        values: {'flag': true},
        timeout: const Duration(milliseconds: 500),
        logger: logger,
      );
      final client = testClient.client;
      final readyEvents = <ClientReadyEvent>[];
      client.onClientReady.listen(readyEvents.add);
      testClient.failInitialization();

      final stopwatch = Stopwatch()..start();
      await client.initialize(_userA);
      await pumpEventQueue();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(client.isReady, isFalse);
      expect(client.isInitializing, isFalse);
      expect(client.context, isNull);
      expect(readyEvents, isEmpty);
      expect(
        logger.errorMessages.single,
        allOf(
          startsWith('[InMemoryConnection]'),
          contains('status: 401'),
          contains('failed this initialization'),
        ),
      );
      expect(logger.warnings, isEmpty);
    });

    test('failInitialization fails an attempt that is already held', () async {
      final testClient = create(
        timeout: const Duration(milliseconds: 500),
        logger: logger,
      );
      final client = testClient.client;
      testClient.holdInitialization();

      final initialization = client.initialize();
      await pumpEventQueue();
      testClient.failInitialization();
      await initialization;

      expect(client.isReady, isFalse);
      expect(client.isInitializing, isFalse);
      expect(logger.errorMessages, hasLength(1));
    });

    test(
      'S25 the attempt after a failure succeeds with the stored values',
      () async {
        final testClient = create(logger: logger);
        final client = testClient.client;
        testClient.failInitialization();
        await client.initialize();
        expect(client.isReady, isFalse);

        testClient.setValue('flag', true);
        await client.initialize();

        expect(client.isReady, isTrue);
        expect(client.getValue('flag', false), isTrue);
      },
    );

    test(
      'S38 completeInitialization before initialize disarms the hold',
      () async {
        final testClient = create(values: {'flag': true});
        testClient.holdInitialization();
        testClient.completeInitialization();

        await testClient.client.initialize();

        expect(testClient.client.isReady, isTrue);
      },
    );

    test('S40 replaceValues disarms a hold and a failure', () async {
      final testClient = create(values: {'flag': true}, logger: logger);
      testClient.holdInitialization();
      testClient.replaceValues({'count': 1});
      await testClient.client.initialize();
      expect(testClient.client.isReady, isTrue);
      expect(testClient.client.getValue('count', 0), 1);
      expect(
        testClient.client.evaluate('flag', false).reason,
        EvaluationReason.configStateMissing,
      );

      testClient.failInitialization();
      testClient.replaceValues({'count': 2});
      await testClient.client.initialize();

      expect(testClient.client.isReady, isTrue);
      expect(testClient.client.getValue('count', 0), 2);
      expect(logger.errorMessages, isEmpty);
    });

    test('holding twice arms one hold', () async {
      final testClient = create(values: {'flag': true});
      testClient.holdInitialization();
      testClient.holdInitialization();

      final initialization = testClient.client.initialize();
      await pumpEventQueue();
      testClient.completeInitialization();
      await initialization;
      expect(testClient.client.isReady, isTrue);

      await testClient.client.initialize();

      expect(testClient.client.isReady, isTrue);
    });

    test('S33 disposing during a held initialize ends it promptly and leaves '
        'no timer', () {
      fakeAsync((async) {
        final testClient = createTestClient(
          values: {'flag': true},
          timeout: const Duration(seconds: 3),
          logger: logger,
        );
        final client = testClient.client;
        testClient.holdInitialization();

        bool? readyOnReturn;
        unawaited(
          client.initialize().then((_) => readyOnReturn = client.isReady),
        );
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        client.dispose();
        async.flushMicrotasks();

        expect(readyOnReturn, isFalse);
        expect(async.pendingTimers, isEmpty);
        expect(
          logger.warnings,
          contains(contains('Timed out waiting for initialization')),
        );
      });
    });

    test('S17 nothing is left running after dispose', () {
      fakeAsync((async) {
        final testClient = createTestClient(
          values: {'flag': true},
          logger: logger,
        );
        final client = testClient.client;
        final seen = <bool>[];
        client.watch('flag', false).listen(seen.add);

        unawaited(client.initialize());
        async.flushMicrotasks();
        expect(client.isReady, isTrue);
        testClient.setValue('flag', false);
        async.flushMicrotasks();
        expect(seen, [false, true, false]);

        client.dispose();
        async.flushMicrotasks();

        expect(async.pendingTimers, isEmpty);
        expect(logger.warnings, isEmpty);
      });
    });

    test('reads nothing from the platform', () async {
      final testClient = create(logger: logger);

      await testClient.client.initialize();
      await pumpEventQueue();

      expect(logger.messages, isNot(contains(contains('app name'))));
      expect(logger.messages, isNot(contains(contains('widgets binding'))));
    });
  });

  group('context updates', () {
    test(
      'S13 contextUpdates records initialize and updateContext only',
      () async {
        final testClient = create();
        final client = testClient.client;

        await client.initialize(_userA);
        await client.updateContext(_userB);
        client.pauseNetwork();
        await client.resumeNetwork();

        expect(testClient.contextUpdates, [_userA, _userB]);
        expect(client.isReady, isTrue);
      },
    );

    test('initialize without a context records an empty context', () async {
      final testClient = create();

      await testClient.client.initialize();

      expect(testClient.contextUpdates, [const ConfigDirectorContext()]);
    });

    test('S26 a held updateContext stays pending until completed', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      await client.initialize(_userA);
      final readyEvents = <ClientReadyEvent>[];
      client.onClientReady.listen(readyEvents.add);
      testClient.holdContextUpdate();

      final update = client.updateContext(_userB);
      await pumpEventQueue();
      expect(client.isReady, isFalse);
      expect(client.context, _userA);
      expect(client.getValue('flag', false), isTrue);

      testClient.completeContextUpdate();
      await update;
      await pumpEventQueue();

      expect(client.isReady, isTrue);
      expect(client.context, _userB);
      expect(testClient.contextUpdates, [_userA, _userB]);
      expect(readyEvents.single.action, ClientConnectAction.contextUpdate);
    });

    test('completing a hold right before a new attempt delivers nothing to '
        'the new attempt', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      testClient.holdInitialization();
      testClient.holdContextUpdate();
      final initialization = client.initialize(_userA);
      await pumpEventQueue();

      testClient.completeInitialization();
      final update = client.updateContext(_userB);
      await pumpEventQueue();

      expect(client.isReady, isFalse);
      await initialization;
      expect(client.isReady, isFalse);

      testClient.completeContextUpdate();
      await update;
      expect(client.isReady, isTrue);
      expect(client.context, _userB);
    });

    test('S42 an initialization hold never holds an updateContext', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      await client.initialize(_userA);
      testClient.holdInitialization();

      await client.updateContext(_userB);
      expect(client.isReady, isTrue);
      expect(testClient.contextUpdates, [_userA, _userB]);

      final initialization = client.initialize(_userA);
      await pumpEventQueue();
      expect(client.isReady, isFalse);
      testClient.completeInitialization();
      await initialization;
      expect(client.isReady, isTrue);
    });

    test('S43 a failed updateContext completes promptly and serves the last '
        'values', () async {
      final testClient = create(
        values: {'flag': true},
        timeout: const Duration(milliseconds: 500),
        logger: logger,
      );
      final client = testClient.client;
      await client.initialize(_userA);
      testClient.failContextUpdate();

      final stopwatch = Stopwatch()..start();
      await client.updateContext(_userB);

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(client.isReady, isFalse);
      expect(client.context, _userA);
      expect(client.getValue('flag', false), isTrue);
      expect(
        logger.errorMessages.single,
        contains('failed this context update'),
      );
    });

    test('S44 a resume is never held and leaves the context update hold '
        'armed', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      await client.initialize(_userA);
      testClient.holdContextUpdate();
      client.pauseNetwork();
      expect(client.isReady, isFalse);

      await client.resumeNetwork();
      expect(client.isReady, isTrue);
      expect(client.getValue('flag', false), isTrue);

      final update = client.updateContext(_userB);
      await pumpEventQueue();
      expect(client.isReady, isFalse);
      testClient.completeContextUpdate();
      await update;
      expect(client.isReady, isTrue);
    });

    test('values set while paused are delivered on resume', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      await client.initialize();
      client.pauseNetwork();

      testClient.setValue('flag', false);
      await pumpEventQueue();
      expect(client.getValue('flag', true), isTrue);

      await client.resumeNetwork();

      expect(client.getValue('flag', true), isFalse);
    });
  });

  group('after dispose', () {
    test('S14 the controls are silent no-ops', () async {
      final testClient = create(values: {'flag': true});
      final client = testClient.client;
      final seen = <bool>[];
      client.watch('flag', false).listen(seen.add);
      await client.initialize();
      await pumpEventQueue();
      final before = seen.length;

      client.dispose();
      testClient.setValue('flag', false);
      testClient.removeValue('flag');
      testClient.replaceValues({'count': 1});
      testClient.holdInitialization();
      testClient.completeInitialization();
      testClient.failInitialization();
      testClient.holdContextUpdate();
      testClient.completeContextUpdate();
      testClient.failContextUpdate();
      await pumpEventQueue();

      expect(seen.length, before);
      expect(client.isReady, isFalse);
    });
  });

  group('widgets', () {
    testWidgets('S16 a StreamBuilder over watch rebuilds on setValue and '
        'removeValue', (tester) async {
      final testClient = create(values: {'greeting': 'hello'});
      final client = testClient.client;
      await tester.pumpWidget(_Greeting(client));
      expect(find.text('fallback'), findsOneWidget);

      unawaited(client.initialize());
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);

      testClient.setValue('greeting', 'hi');
      await tester.pumpAndSettle();
      expect(find.text('hi'), findsOneWidget);

      testClient.removeValue('greeting');
      await tester.pumpAndSettle();
      expect(find.text('fallback'), findsOneWidget);
    });
  });

  testWidgets('backgrounding the app does not pause the test client', (
    tester,
  ) async {
    final testClient = create(values: {'flag': true});
    final client = testClient.client;
    unawaited(client.initialize());
    await tester.pumpAndSettle();
    expect(client.isReady, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(client.isReady, isTrue);

    testClient.setValue('flag', false);
    await tester.pumpAndSettle();
    expect(client.getValue('flag', true), isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(testClient.contextUpdates, hasLength(1));
  });

  test('the default logger is the SDK console logger', () async {
    final printed = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    addTearDown(() => debugPrint = previous);
    final testClient = create(timeout: const Duration(milliseconds: 500));
    testClient.failInitialization();

    await testClient.client.initialize();

    expect(
      printed.single,
      contains(
        '[ERROR] [ConfigDirector:flutter-client-sdk] [InMemoryConnection]',
      ),
    );
  });
}

class _Greeting extends StatefulWidget {
  const _Greeting(this.client);

  final ConfigDirectorClient client;

  @override
  State<_Greeting> createState() => _GreetingState();
}

class _GreetingState extends State<_Greeting> {
  late final Stream<String> _greeting = widget.client.watch(
    'greeting',
    'fallback',
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<String>(
    stream: _greeting,
    initialData: 'fallback',
    builder: (context, snapshot) =>
        Text(snapshot.data ?? 'fallback', textDirection: TextDirection.ltr),
  );
}
