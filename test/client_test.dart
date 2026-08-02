import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/src/client/default_config_director_client.dart';
import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
import 'package:configdirector_flutter_client_sdk/src/transport/transport.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeTransport transport;
  late FakeLifecycleWatcher lifecycleWatcher;
  late RecordingLogger logger;
  late List<TransportOptions> transportOptions;

  DefaultConfigDirectorClient createClient({
    ConnectionOptions? connection,
    ConfigDirectorMetaContext? metadata,
    String? Function()? userAgentResolver,
  }) => DefaultConfigDirectorClient(
    'a-client-sdk-key',
    options: ConfigDirectorClientOptions(
      logger: logger,
      metadata: metadata,
      connection:
          connection ??
          const ConnectionOptions(timeout: Duration(milliseconds: 50)),
    ),
    transportFactory: (options) {
      transportOptions.add(options);
      return transport;
    },
    lifecycleWatcher: lifecycleWatcher,
    userAgentResolver: userAgentResolver,
  );

  setUp(() {
    transport = FakeTransport();
    lifecycleWatcher = FakeLifecycleWatcher();
    logger = RecordingLogger();
    transportOptions = [];
  });

  group('meta context', () {
    test('identifies the SDK and the host platform', () {
      autoDispose(
        createClient(
          metadata: const ConfigDirectorMetaContext(
            appName: 'my-app',
            appVersion: '1.2.3',
          ),
        ),
      );

      expect(transportOptions.single.metaContext.toJson(), {
        'appName': 'my-app',
        'appVersion': '1.2.3',
        'sdkName': 'flutter-client-sdk',
        'sdkVersion': constants.sdkVersion,
        // The browser's user agent on web, the platform name everywhere else.
        'userAgent': kIsWeb ? contains('Mozilla/') : defaultTargetPlatform.name,
      });
    });

    test('omits the user agent when the platform reports none', () {
      autoDispose(createClient(userAgentResolver: () => null));

      expect(
        transportOptions.single.metaContext.toJson(),
        isNot(contains('userAgent')),
      );
    });

    test('gives each client a distinct v4 instance id', () {
      autoDispose(createClient());
      final firstId = transportOptions.single.instanceId;
      transport = FakeTransport();
      autoDispose(createClient());
      final secondId = transportOptions.last.instanceId;

      expect(
        firstId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(secondId, isNot(firstId));
    });
  });

  group('construction', () {
    test('rejects a blank SDK key', () {
      expect(
        () => DefaultConfigDirectorClient(
          '   ',
          transportFactory: (_) => transport,
        ),
        throwsA(isA<ConfigDirectorValidationError>()),
      );
    });

    test('rejects a relative base URL', () {
      expect(
        () => DefaultConfigDirectorClient(
          'a-key',
          options: ConfigDirectorClientOptions(
            connection: ConnectionOptions(baseUrl: Uri.parse('/proxy')),
          ),
          transportFactory: (_) => transport,
        ),
        throwsA(isA<ConfigDirectorValidationError>()),
      );
    });

    test('starts out neither ready nor initializing', () {
      final client = autoDispose(createClient());

      expect(client.isReady, isFalse);
      expect(client.isInitializing, isFalse);
      expect(client.context, isNull);
    });
  });

  group('initialize', () {
    test('becomes ready once the first config set arrives', () async {
      final client = autoDispose(createClient());
      const context = ConfigDirectorContext(id: 'user-1');

      final readyEvents = <ClientReadyEvent>[];
      client.onClientReady.listen(readyEvents.add);

      final initialization = client.initialize(context);
      expect(client.isInitializing, isTrue);

      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;

      expect(client.isReady, isTrue);
      expect(client.isInitializing, isFalse);
      expect(client.context, context);
      expect(transport.connectCalls.single.context, context);

      await pumpEventQueue();
      expect(readyEvents.single.action, ClientConnectAction.initialization);
    });

    test('connects with an empty context when none is given', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      expect(
        transport.connectCalls.single.context,
        const ConfigDirectorContext(),
      );
      expect(client.context, isNull);
    });

    test(
      'returns without becoming ready when no config set arrives in time',
      () async {
        final client = autoDispose(createClient());

        await client.initialize();

        expect(client.isReady, isFalse);
        expect(
          logger.messages.any(
            (message) =>
                message.contains('Timed out waiting for initialization'),
          ),
          isTrue,
        );
      },
    );

    test('becomes ready if the config set arrives after the timeout', () async {
      final client = autoDispose(createClient());

      await client.initialize();
      expect(client.isReady, isFalse);

      transport.emitConfigSet(configSet(configs: const {}));
      await pumpEventQueue();

      expect(client.isReady, isTrue);
      expect(client.isInitializing, isFalse);
    });

    test('logs and swallows an unrecoverable transport error', () async {
      transport.connectError = const ConfigDirectorConnectionError(
        'Invalid SDK key',
        401,
      );
      final client = autoDispose(createClient());

      await client.initialize();

      expect(client.isReady, isFalse);
      expect(
        logger.messages.any(
          (message) =>
              message.contains('An error occurred during initialization'),
        ),
        isTrue,
      );
    });
  });

  group('getValue', () {
    test('returns the default value before the client is ready', () async {
      final client = autoDispose(createClient());

      expect(client.getValue('dark-mode', false), isFalse);
      expect(client.getValue('greeting', 'hi'), 'hi');
    });

    test('returns evaluated values once config state is received', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
            'max-items': configState('max-items', ConfigType.integer, '25'),
            'greeting': configState('greeting', ConfigType.string, 'hello'),
          },
        ),
      );
      await initialization;

      expect(client.getValue('dark-mode', false), isTrue);
      expect(client.getValue('max-items', 0), 25);
      expect(client.getValue('greeting', 'hi'), 'hello');
      expect(client.getValue('unknown', 'fallback'), 'fallback');
    });

    test('rejects a function default value', () {
      final client = autoDispose(createClient());

      expect(
        () => client.getValue('a-key', () {}),
        throwsA(isA<ConfigDirectorValidationError>()),
      );
    });

    test('emits an evaluation event with the reason', () async {
      final client = autoDispose(createClient());
      final evaluations = <ConfigEvaluation>[];
      client.onConfigEvaluated.listen(
        (event) => evaluations.add(event.evaluation),
      );

      client.getValue('dark-mode', false);
      await pumpEventQueue();

      expect(evaluations.single.key, 'dark-mode');
      expect(evaluations.single.isDefaultValue, isTrue);
      expect(evaluations.single.reason, EvaluationReason.clientNotReady);
    });

    test('reports a missing config once the client is ready', () async {
      final client = autoDispose(createClient());
      final evaluations = <ConfigEvaluation>[];

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      client.onConfigEvaluated.listen(
        (event) => evaluations.add(event.evaluation),
      );
      client.getValue('dark-mode', false);
      await pumpEventQueue();

      expect(evaluations.single.reason, EvaluationReason.configStateMissing);
    });
  });

  group('config sets', () {
    test('merges a delta into the existing config state', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
            'greeting': configState('greeting', ConfigType.string, 'hello'),
          },
        ),
      );
      await initialization;

      transport.emitConfigSet(
        configSet(
          kind: ConfigSetKind.delta,
          configs: {
            'greeting': configState('greeting', ConfigType.string, 'bye'),
          },
        ),
      );
      await pumpEventQueue();

      expect(client.getValue('dark-mode', false), isTrue);
      expect(client.getValue('greeting', ''), 'bye');
    });

    test('replaces the existing config state on a full set', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;

      transport.emitConfigSet(
        configSet(
          configs: {
            'greeting': configState('greeting', ConfigType.string, 'bye'),
          },
        ),
      );
      await pumpEventQueue();

      expect(client.getValue('dark-mode', false), isFalse);
      expect(client.getValue('greeting', ''), 'bye');
    });

    test('emits the keys contained in the update', () async {
      final client = autoDispose(createClient());
      final updates = <List<String>>[];
      client.onConfigsUpdated.listen((event) => updates.add(event.keys));

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;
      await pumpEventQueue();

      expect(updates.single, ['dark-mode']);
    });
  });

  group('watch', () {
    test('emits the current value on subscription', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;

      expect(await client.watch('dark-mode', false).first, isTrue);
    });

    test('emits the default value when there is no config state yet', () async {
      final client = autoDispose(createClient());

      expect(await client.watch('dark-mode', false).first, isFalse);
    });

    test('emits when the evaluated value changes', () async {
      final client = autoDispose(createClient());
      final values = <bool>[];
      final subscription = client.watch('dark-mode', false).listen(values.add);

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;
      await pumpEventQueue();

      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'false'),
          },
        ),
      );
      await pumpEventQueue();

      expect(values, [false, true, false]);
      await subscription.cancel();
    });

    test('does not re-emit an unchanged value', () async {
      final client = autoDispose(createClient());
      final values = <bool>[];
      final subscription = client.watch('dark-mode', false).listen(values.add);

      final initialization = client.initialize();
      for (var i = 0; i < 3; i++) {
        transport.emitConfigSet(
          configSet(
            configs: {
              'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
            },
          ),
        );
      }
      await initialization;
      await pumpEventQueue();

      expect(values, [false, true]);
      await subscription.cancel();
    });

    test('stops emitting once the subscription is cancelled', () async {
      final client = autoDispose(createClient());
      final values = <bool>[];
      final subscription = client.watch('dark-mode', false).listen(values.add);
      await pumpEventQueue();
      await subscription.cancel();

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;
      await pumpEventQueue();

      expect(values, [false]);
    });

    test('unwatch closes every stream for the key', () async {
      final client = autoDispose(createClient());
      var isDone = false;
      client
          .watch('dark-mode', false)
          .listen(null, onDone: () => isDone = true);
      await pumpEventQueue();

      client.unwatch('dark-mode');
      await pumpEventQueue();

      expect(isDone, isTrue);
    });

    test('unwatchAll closes every stream', () async {
      final client = autoDispose(createClient());
      final done = <String>[];
      client
          .watch('dark-mode', false)
          .listen(null, onDone: () => done.add('dark-mode'));
      client
          .watch('greeting', '')
          .listen(null, onDone: () => done.add('greeting'));
      await pumpEventQueue();

      client.unwatchAll();
      await pumpEventQueue();

      expect(done, unorderedEquals(['dark-mode', 'greeting']));
    });
  });

  group('updateContext', () {
    test('reconnects and applies the new context', () async {
      final client = autoDispose(createClient());
      const updatedContext = ConfigDirectorContext(id: 'user-2', name: 'Ada');
      final contexts = <ConfigDirectorContext?>[];
      client.onContextUpdated.listen((event) => contexts.add(event.context));

      final initialization = client.initialize(
        const ConfigDirectorContext(id: 'user-1'),
      );
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      final update = client.updateContext(updatedContext);
      transport.emitConfigSet(configSet(configs: const {}));
      await update;
      await pumpEventQueue();

      expect(transport.connectCalls.length, 2);
      expect(transport.connectCalls.last.context, updatedContext);
      expect(client.context, updatedContext);
      expect(contexts, [
        const ConfigDirectorContext(id: 'user-1'),
        updatedContext,
      ]);
    });

    test('re-evaluates watched configs against the new context', () async {
      final client = autoDispose(createClient());
      final values = <String>[];
      final subscription = client.watch('greeting', 'none').listen(values.add);

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'greeting': configState('greeting', ConfigType.string, 'hello'),
          },
        ),
      );
      await initialization;
      await pumpEventQueue();

      final update = client.updateContext(
        const ConfigDirectorContext(id: 'user-2'),
      );
      transport.emitConfigSet(
        configSet(
          configs: {
            'greeting': configState('greeting', ConfigType.string, 'hola'),
          },
        ),
      );
      await update;
      await pumpEventQueue();

      expect(values, ['none', 'hello', 'hola']);
      await subscription.cancel();
    });
  });

  group('network', () {
    test('pauseNetwork closes the transport and clears readiness', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      client.pauseNetwork();

      expect(transport.closeCount, 1);
      expect(client.isReady, isFalse);
    });

    test('resumeNetwork reconnects with the last context', () async {
      final client = autoDispose(createClient());
      const context = ConfigDirectorContext(id: 'user-1');

      final initialization = client.initialize(context);
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      client.pauseNetwork();
      final resume = client.resumeNetwork();
      transport.emitConfigSet(configSet(configs: const {}));
      await resume;

      expect(transport.connectCalls.last.context, context);
      expect(client.isReady, isTrue);
    });

    test('keeps config state across a pause', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await initialization;

      client.pauseNetwork();

      expect(client.getValue('dark-mode', false), isTrue);
    });
  });

  group('app lifecycle', () {
    test('pauses when backgrounded and resumes when foregrounded', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      lifecycleWatcher.send(AppLifecycleState.paused);
      expect(transport.closeCount, 1);

      lifecycleWatcher.send(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(transport.connectCalls.length, 2);
      expect(
        transport.connectCalls.last.context,
        const ConfigDirectorContext(),
      );
    });

    test('ignores transient interruptions', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      lifecycleWatcher
        ..send(AppLifecycleState.inactive)
        ..send(AppLifecycleState.hidden);

      expect(transport.closeCount, 0);
    });

    test('does nothing before the client has connected', () {
      autoDispose(createClient());

      lifecycleWatcher
        ..send(AppLifecycleState.paused)
        ..send(AppLifecycleState.resumed);

      expect(transport.closeCount, 0);
      expect(transport.connectCalls, isEmpty);
    });

    test('does not resume a connection paused manually', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      client.pauseNetwork();
      lifecycleWatcher.send(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(transport.connectCalls.length, 1);
    });

    test('is not registered when disabled', () {
      autoDispose(
        createClient(
          connection: const ConnectionOptions(pauseWhileBackgrounded: false),
        ),
      );

      expect(lifecycleWatcher.isStarted, isFalse);
    });
  });

  group('dispose', () {
    test('disposes the transport and stops watching the lifecycle', () {
      final client = createClient();

      client.dispose();

      expect(transport.disposed, isTrue);
      expect(lifecycleWatcher.stopped, isTrue);
    });

    test('closes watch and event streams', () async {
      final client = createClient();
      var watchDone = false;
      var eventsDone = false;
      client
          .watch('dark-mode', false)
          .listen(null, onDone: () => watchDone = true);
      client.onConfigsUpdated.listen(null, onDone: () => eventsDone = true);
      await pumpEventQueue();

      client.dispose();
      await pumpEventQueue();

      expect(watchDone, isTrue);
      expect(eventsDone, isTrue);
    });

    test('is safe to call twice', () {
      final client = createClient();

      client.dispose();

      expect(client.dispose, returnsNormally);
    });
  });
}

/// Registers [client] for disposal at the end of the test and returns it.
DefaultConfigDirectorClient autoDispose(DefaultConfigDirectorClient client) {
  addTearDown(client.dispose);
  return client;
}
