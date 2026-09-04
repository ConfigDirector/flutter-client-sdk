import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/src/client/default_config_director_client.dart';
import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
import 'package:configdirector_flutter_client_sdk/src/platform/app_info.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_client.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_value.dart';
import 'package:configdirector_flutter_client_sdk/src/transport/transport.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'support/fakes.dart';

void main() {
  late FakeTransport transport;
  late FakeLifecycleWatcher lifecycleWatcher;
  late FakeTelemetryClient telemetry;
  late RecordingLogger logger;
  late List<TransportOptions> transportOptions;

  DefaultConfigDirectorClient createClient({
    ConnectionOptions? connection,
    ConfigDirectorMetaContext? metadata,
    String? Function()? userAgentResolver,
    AppInfoResolver? appInfoResolver,
    TelemetryClient? telemetryClient,
  }) => DefaultConfigDirectorClient(
    'a-client-sdk-key',
    options: ConfigDirectorClientOptions(
      logger: logger,
      metadata: metadata,
      connection:
          connection ??
          const ConnectionOptions(timeout: Duration(milliseconds: 50)),
    ),
    // Telemetry is faked by default so that tests neither start the telemetry
    // isolate nor leave its flush timer running.
    telemetryClient: telemetryClient ?? telemetry,
    transportFactory: (options) {
      transportOptions.add(options);
      return transport;
    },
    lifecycleWatcher: lifecycleWatcher,
    userAgentResolver: userAgentResolver,
    // The platform is never consulted unless a test asks for it, so tests do
    // not depend on what the host running them reports.
    appInfoResolver:
        appInfoResolver ?? () async => const ConfigDirectorMetaContext(),
  );

  setUp(() {
    transport = FakeTransport();
    lifecycleWatcher = FakeLifecycleWatcher();
    telemetry = FakeTelemetryClient();
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

    test(
      'falls back to the app name and version reported by the platform',
      () async {
        autoDispose(
          createClient(
            appInfoResolver: () async => const ConfigDirectorMetaContext(
              appName: 'detected-app',
              appVersion: '4.5.6',
            ),
          ),
        );
        await pumpEventQueue();

        expect(transportOptions.single.metaContext.toJson(), {
          'appName': 'detected-app',
          'appVersion': '4.5.6',
          'sdkName': 'flutter-client-sdk',
          'sdkVersion': constants.sdkVersion,
          'userAgent': anything,
        });
      },
    );

    test('keeps the provided app name over the platform one, and fills in the '
        'version that was left out', () async {
      autoDispose(
        createClient(
          metadata: const ConfigDirectorMetaContext(appName: 'my-app'),
          appInfoResolver: () async => const ConfigDirectorMetaContext(
            appName: 'detected-app',
            appVersion: '4.5.6',
          ),
        ),
      );
      await pumpEventQueue();

      expect(
        transportOptions.single.metaContext.toJson(),
        allOf(
          containsPair('appName', 'my-app'),
          containsPair('appVersion', '4.5.6'),
        ),
      );
    });

    test('does not consult the platform when both were provided', () async {
      var resolverCalls = 0;
      autoDispose(
        createClient(
          metadata: const ConfigDirectorMetaContext(
            appName: 'my-app',
            appVersion: '1.2.3',
          ),
          appInfoResolver: () async {
            resolverCalls++;
            return const ConfigDirectorMetaContext();
          },
        ),
      );
      await pumpEventQueue();

      expect(resolverCalls, 0);
      expect(logger.messages, isNot(contains(contains('could not find'))));
    });

    test(
      'logs what it could not find when the platform reports nothing',
      () async {
        autoDispose(createClient());
        await pumpEventQueue();

        expect(
          logger.messages,
          contains(contains('could not find an app name and version')),
        );
      },
    );

    test(
      'logs only the app version when that is all that is missing',
      () async {
        autoDispose(
          createClient(
            metadata: const ConfigDirectorMetaContext(appName: 'my-app'),
          ),
        );
        await pumpEventQueue();

        expect(
          logger.messages,
          contains(contains('could not find an app version')),
        );
      },
    );

    test('still connects when reading the app info fails', () async {
      final client = autoDispose(
        createClient(
          appInfoResolver: () async => throw StateError('no plugin'),
        ),
      );

      await client.initialize();

      expect(transport.connectCalls, hasLength(1));
      expect(
        transportOptions.single.metaContext.toJson(),
        allOf(isNot(contains('appName')), isNot(contains('appVersion'))),
      );
      expect(
        logger.messages,
        contains(contains('could not find an app name and version')),
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
        throwsA(isA<ConfigDirectorValidationException>()),
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
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('rejects a timeout that is not positive', () {
      expect(
        () => DefaultConfigDirectorClient(
          'a-key',
          options: const ConfigDirectorClientOptions(
            connection: ConnectionOptions(timeout: Duration.zero),
          ),
          transportFactory: (_) => transport,
        ),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('rejects a polling interval that is not positive when polling', () {
      expect(
        () => DefaultConfigDirectorClient(
          'a-key',
          options: const ConfigDirectorClientOptions(
            connection: ConnectionOptions(
              mode: ConnectionMode.polling,
              pollingInterval: Duration.zero,
            ),
          ),
          transportFactory: (_) => transport,
        ),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('ignores the polling interval in the other modes', () {
      autoDispose(
        createClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.streaming,
            pollingInterval: Duration.zero,
          ),
        ),
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

    test('waits the full timeout for a config set even when reading the app '
        'info took a while', () async {
      final appInfo = Completer<ConfigDirectorMetaContext>();
      final client = autoDispose(
        createClient(
          connection: const ConnectionOptions(
            timeout: Duration(milliseconds: 200),
          ),
          appInfoResolver: () => appInfo.future,
        ),
      );
      transport.holdConnects = true;

      bool? readyOnReturn;
      final initialization = client.initialize().then(
        (_) => readyOnReturn = client.isReady,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      appInfo.complete(const ConfigDirectorMetaContext());
      await pumpEventQueue();
      transport.heldConnects.single.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      expect(readyOnReturn, isTrue);
      expect(logger.messages, isNot(contains(contains('Timed out'))));
    });

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
      transport.connectError = const ConfigDirectorConnectionException(
        'Invalid SDK key',
        401,
      );
      final client = autoDispose(createClient());

      await client.initialize();

      expect(client.isReady, isFalse);
      expect(client.isInitializing, isFalse);
      expect(
        logger.messages.any(
          (message) =>
              message.contains('An error occurred during initialization'),
        ),
        isTrue,
      );
    });

    test(
      'is no longer initializing once initialize gives up waiting',
      () async {
        final client = autoDispose(createClient());

        await client.initialize();

        expect(client.isReady, isFalse);
        expect(client.isInitializing, isFalse);
      },
    );
  });

  group('polling', () {
    test('adopts the context when the first fetch fails transiently', () async {
      var fetches = 0;
      final client = autoDispose(
        DefaultConfigDirectorClient(
          'a-client-sdk-key',
          options: ConfigDirectorClientOptions(
            logger: logger,
            connection: const ConnectionOptions(
              mode: ConnectionMode.polling,
              timeout: Duration(milliseconds: 50),
            ),
          ),
          httpClient: MockClient((request) async {
            fetches++;
            return fetches == 1
                ? http.Response('server exploded', 500)
                : http.Response(
                    jsonEncode({'kind': 'full', 'configs': {}}),
                    200,
                  );
          }),
          telemetryClient: telemetry,
          lifecycleWatcher: lifecycleWatcher,
          appInfoResolver: () async => const ConfigDirectorMetaContext(),
        ),
      );
      const context = ConfigDirectorContext(id: 'user-1');

      await client.initialize(context);

      expect(client.context, context);
      expect(telemetry.contextUpdates, [context]);
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
        throwsA(isA<ConfigDirectorValidationException>()),
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

    test('does not re-emit an unchanged JSON document', () async {
      final client = autoDispose(createClient());
      final values = <Map<String, Object?>>[];
      final subscription = client
          .watch('layout', <String, Object?>{})
          .listen(values.add);

      final initialization = client.initialize();
      for (var i = 0; i < 3; i++) {
        transport.emitConfigSet(
          configSet(
            configs: {
              'layout': configState(
                'layout',
                ConfigType.json,
                '{"columns": 2, "tags": ["a", "b"]}',
              ),
            },
          ),
        );
      }
      await initialization;
      await pumpEventQueue();

      expect(values, [
        <String, Object?>{},
        {
          'columns': 2,
          'tags': ['a', 'b'],
        },
      ]);
      await subscription.cancel();
    });

    test('falls back to the default when a full set drops the key', () async {
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
            'greeting': configState('greeting', ConfigType.string, 'bye'),
          },
        ),
      );
      await pumpEventQueue();

      expect(values, [false, true, false]);
      expect(client.getValue('dark-mode', false), isFalse);
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

    test('an update overtaken by a newer one does not take effect', () async {
      final client = autoDispose(createClient());
      const slow = ConfigDirectorContext(id: 'user-slow');
      const fast = ConfigDirectorContext(id: 'user-fast');
      final contexts = <ConfigDirectorContext?>[];
      client.onContextUpdated.listen((event) => contexts.add(event.context));

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      transport.holdConnects = true;
      final slowUpdate = client.updateContext(slow);
      final fastUpdate = client.updateContext(fast);
      await pumpEventQueue();
      transport.heldConnects[1].complete();
      await pumpEventQueue();
      transport.emitConfigSet(configSet(configs: const {}));
      transport.heldConnects[0].complete();
      await Future.wait([slowUpdate, fastUpdate]);
      await pumpEventQueue();

      expect(client.context, fast);
      expect(telemetry.contextUpdates.last, fast);
      expect(contexts, [null, fast]);
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

    test('resuming after a pause during initialization keeps the requested '
        'context', () async {
      final client = autoDispose(createClient());
      const context = ConfigDirectorContext(id: 'user-1');

      transport.holdConnects = true;
      final initialization = client.initialize(context);
      await pumpEventQueue();
      client.pauseNetwork();
      final resume = client.resumeNetwork();
      await pumpEventQueue();
      transport.heldConnects[1].complete();
      transport.emitConfigSet(configSet(configs: const {}));
      transport.heldConnects[0].complete();
      await Future.wait([initialization, resume]);

      expect(transport.connectCalls.last.context, context);
      expect(client.context, context);
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

    test('does not pause the connection when disabled', () async {
      final client = autoDispose(
        createClient(
          connection: const ConnectionOptions(pauseWhileBackgrounded: false),
        ),
      );

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      lifecycleWatcher.send(AppLifecycleState.paused);

      expect(transport.closeCount, 0);
    });

    // Telemetry is reported when the app leaves the foreground, so the
    // lifecycle is followed whether or not the connection is paused with it.
    test('is followed even when pausing is disabled', () {
      autoDispose(
        createClient(
          connection: const ConnectionOptions(pauseWhileBackgrounded: false),
        ),
      );

      lifecycleWatcher.send(AppLifecycleState.hidden);

      expect(lifecycleWatcher.isStarted, isTrue);
      expect(telemetry.flushCount, 1);
    });

    test('flushes telemetry when the app leaves the foreground', () async {
      autoDispose(createClient());

      lifecycleWatcher.send(AppLifecycleState.inactive);
      expect(telemetry.flushCount, 0);

      lifecycleWatcher.send(AppLifecycleState.hidden);
      lifecycleWatcher.send(AppLifecycleState.paused);

      expect(telemetry.flushCount, 2);
    });
  });

  group('telemetry', () {
    test('records an evaluation against the current context', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize(
        const ConfigDirectorContext(id: 'user-123'),
      );
      transport.emitConfigSet(
        configSet(
          configs: {
            'max-items': configState('max-items', ConfigType.integer, '25'),
          },
        ),
      );
      await initialization;

      client.getValue('max-items', 10);

      final event = telemetry.events.single;
      expect(event.key, 'max-items');
      expect(event.contextId, 'user-123');
      expect(event.type, ConfigType.integer);
      expect(event.requestedType, 'int');
      expect(event.defaultValue, const TelemetryValue(value: '10'));
      expect(event.evaluatedValue, const TelemetryValue(value: '25'));
      expect(event.evaluatedValueId, 'value-id');
      expect(event.usedDefault, isFalse);
      expect(event.evaluationReason, EvaluationReason.foundMatch);
    });

    test('records an evaluation that fell back to the default value', () {
      final client = autoDispose(createClient());

      client.getValue('greeting', 'hi');

      final event = telemetry.events.single;
      expect(event.key, 'greeting');
      expect(event.type, isNull);
      expect(event.requestedType, 'String');
      expect(event.evaluatedValue, const TelemetryValue(value: 'hi'));
      expect(event.evaluatedValueId, isNull);
      expect(event.usedDefault, isTrue);
      expect(event.evaluationReason, EvaluationReason.clientNotReady);
    });

    test('records the evaluations behind a watch stream', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;
      client.watch('dark-mode', false).listen(null);
      await pumpEventQueue();

      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
          },
        ),
      );
      await pumpEventQueue();

      expect(telemetry.events.map((e) => e.evaluatedValue.value), [
        'false',
        'true',
      ]);
    });

    test('hands the new context over once it takes effect', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;
      await client.updateContext(const ConfigDirectorContext(id: 'user-123'));

      expect(telemetry.contextUpdates, [
        null,
        const ConfigDirectorContext(id: 'user-123'),
      ]);
    });

    test('is not updated when the connection fails', () async {
      final client = autoDispose(createClient());
      transport.connectError = const ConfigDirectorConnectionException('nope');

      await client.initialize(const ConfigDirectorContext(id: 'user-123'));

      expect(telemetry.contextUpdates, isEmpty);
    });

    test('is closed with the client', () {
      createClient().dispose();

      expect(telemetry.closeCount, 1);
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
