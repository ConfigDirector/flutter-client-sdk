import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/src/client/default_config_director_client.dart';
import 'package:configdirector_flutter_client_sdk/src/client_session.dart';
import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
import 'package:configdirector_flutter_client_sdk/src/platform/app_info.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_client.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_value.dart';
import 'package:configdirector_flutter_client_sdk/src/transport/transport.dart';
import 'package:configdirector_flutter_client_sdk/src/sdk_identity.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'support/fakes.dart';

const String _storedInstanceId = '11111111-1111-4111-8111-111111111111';

void main() {
  late FakeTransport transport;
  late FakeLifecycleWatcher lifecycleWatcher;
  late FakeTelemetryClient telemetry;
  late RecordingLogger logger;
  late List<TransportOptions> transportOptions;
  late FakeInstanceIdStorage instanceIdStorage;

  DefaultConfigDirectorClient createClient({
    ConnectionOptions? connection,
    ConfigDirectorMetaContext? metadata,
    String? Function()? userAgentResolver,
    AppInfoResolver? appInfoResolver,
    TelemetryClient? telemetryClient,
    SdkIdentity? identity,
    ClientSession? clientSession,
  }) => DefaultConfigDirectorClient(
    'a-client-sdk-key',
    identity: identity ?? flutterClientSdkIdentity,
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
    instanceIdStorage: instanceIdStorage,
    clientSession: clientSession,
  );

  setUp(() {
    transport = FakeTransport();
    lifecycleWatcher = FakeLifecycleWatcher();
    telemetry = FakeTelemetryClient();
    logger = RecordingLogger();
    transportOptions = [];
    instanceIdStorage = FakeInstanceIdStorage();
  });

  String record({required int createdAt}) =>
      jsonEncode({'v': 1, 'id': _storedInstanceId, 'createdAt': createdAt});

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
  });

  group('client session', () {
    test(
      'connects with the stored instance ID, not marked ephemeral',
      () async {
        instanceIdStorage.record = record(
          createdAt: DateTime.now().millisecondsSinceEpoch - 60000,
        );
        final client = autoDispose(createClient());

        final initialization = client.initialize();
        await pumpEventQueue();
        transport.emitConfigSet(configSet(configs: const {}));
        await initialization;

        expect(transport.connectCalls, hasLength(1));
        expect(
          transportOptions.single.clientSession.instanceId,
          _storedInstanceId,
        );
        expect(transportOptions.single.clientSession.ephemeral, isFalse);
        expect(instanceIdStorage.writes, isEmpty);
      },
    );

    test(
      'generates and stores a v4 instance ID when nothing is stored',
      () async {
        autoDispose(createClient());
        await pumpEventQueue();

        final session = transportOptions.single.clientSession;
        expect(session.instanceId, matches(uuidV4Pattern));
        expect(session.ephemeral, isFalse);
        expect(
          jsonDecode(instanceIdStorage.record!),
          containsPair('id', session.instanceId),
        );
      },
    );

    test('shares the stored instance ID with a client created later', () async {
      autoDispose(createClient());
      await pumpEventQueue();
      final firstId = transportOptions.single.clientSession.instanceId;

      transport = FakeTransport();
      autoDispose(createClient());
      await pumpEventQueue();

      expect(transportOptions.last.clientSession.instanceId, firstId);
      expect(transportOptions.last.clientSession.ephemeral, isFalse);
    });

    test('defers the connection and the telemetry context until the storage '
        'answers', () async {
      instanceIdStorage.record = record(
        createdAt: DateTime.now().millisecondsSinceEpoch - 60000,
      );
      instanceIdStorage.heldRead = Completer<void>();
      final client = autoDispose(createClient());
      const context = ConfigDirectorContext(id: 'user-1');

      final initialization = client.initialize(context);
      await pumpEventQueue();

      expect(transport.connectCalls, isEmpty);
      expect(telemetry.contextUpdates, isEmpty);
      expect(client.getValue('dark-mode', false), isFalse);

      instanceIdStorage.heldRead!.complete();
      await pumpEventQueue();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      expect(transport.connectCalls.single.context, context);
      expect(
        transportOptions.single.clientSession.instanceId,
        _storedInstanceId,
      );
      expect(telemetry.contextUpdates, [context]);
      expect(client.isReady, isTrue);
    });

    test(
      'connects with the provisional instance ID, marked ephemeral, when the '
      'storage has not answered after one second, and keeps it',
      () {
        fakeAsync((async) {
          instanceIdStorage.record = record(
            createdAt: DateTime.now().millisecondsSinceEpoch - 60000,
          );
          instanceIdStorage.heldRead = Completer<void>();
          final client = autoDispose(createClient());

          client.initialize();
          async.elapse(const Duration(milliseconds: 999));

          expect(transport.connectCalls, isEmpty);

          async.elapse(const Duration(milliseconds: 1));

          expect(transport.connectCalls, hasLength(1));
          final session = transportOptions.single.clientSession;
          expect(session.instanceId, matches(uuidV4Pattern));
          expect(session.ephemeral, isTrue);
          expect(instanceIdStorage.writes, isEmpty);

          transport.emitConfigSet(configSet(configs: const {}));
          async.flushMicrotasks();
          instanceIdStorage.heldRead!.complete();
          client.updateContext(const ConfigDirectorContext(id: 'user-1'));
          async.flushMicrotasks();

          expect(transport.connectCalls, hasLength(2));
          expect(transportOptions.single.clientSession, same(session));
        });
      },
    );

    test('connects with an ephemeral instance ID when the storage cannot be '
        'read', () async {
      instanceIdStorage.readFailure = StateError('preferences unavailable');
      final client = autoDispose(createClient());

      await client.initialize();

      expect(transport.connectCalls, hasLength(1));
      expect(transportOptions.single.clientSession.ephemeral, isTrue);
      expect(instanceIdStorage.writes, isEmpty);
    });

    test('connects with the given session as it is', () async {
      const session = ClientSession(instanceId: 'given', ephemeral: true);
      final client = autoDispose(
        createClient(
          clientSession: session,
          connection: const ConnectionOptions(timeout: Duration(seconds: 3)),
        ),
      );

      final initialization = client.initialize();
      await pumpEventQueue();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      expect(transportOptions.single.clientSession, same(session));
      expect(instanceIdStorage.writes, isEmpty);
      expect(logger.warnings, isEmpty);
    });

    test('does not connect when disposed before the session settles', () async {
      instanceIdStorage.heldRead = Completer<void>();
      final client = createClient();

      final initialization = client.initialize();
      await pumpEventQueue();

      client.dispose();
      instanceIdStorage.heldRead!.complete();
      await initialization;

      expect(transport.connectCalls, isEmpty);
      expect(client.isInitializing, isFalse);
    });
  });

  group('wrapper identity', () {
    test('reports the wrapper in place of the SDK', () {
      autoDispose(
        createClient(identity: SdkIdentity.openFeatureProvider('2.0.0')),
      );

      expect(
        transportOptions.single.metaContext.toJson(),
        allOf(
          containsPair('sdkName', 'flutter-openfeature-client-provider'),
          containsPair('sdkVersion', '2.0.0'),
        ),
      );
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

    test('rejects a missing SDK key', () {
      expect(
        () => DefaultConfigDirectorClient(
          null,
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

    test('starts out neither ready nor initializing', () {
      final client = autoDispose(createClient());

      expect(client.isReady, isFalse);
      expect(client.isInitializing, isFalse);
      expect(client.context, isNull);
    });
  });

  group('polling interval', () {
    const shortTimeout = Duration(milliseconds: 50);

    test('polls every 60 seconds unless configured otherwise', () {
      autoDispose(
        createClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.polling,
            timeout: shortTimeout,
          ),
        ),
      );

      expect(
        transportOptions.single.pollingInterval,
        const Duration(seconds: 60),
      );
      expect(logger.warnings, isEmpty);
    });

    test('raises an interval below 30 seconds and warns once', () async {
      final client = autoDispose(
        createClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.polling,
            pollingInterval: Duration(seconds: 10),
            timeout: shortTimeout,
          ),
        ),
      );

      expect(
        transportOptions.single.pollingInterval,
        const Duration(seconds: 30),
      );
      expect(logger.warnings, hasLength(1));
      expect(logger.warnings.single, contains('below the minimum'));

      await client.initialize(const ConfigDirectorContext(id: 'user-1'));
      await client.updateContext(const ConfigDirectorContext(id: 'user-2'));

      expect(
        logger.warnings.where(
          (message) => message.contains('below the minimum'),
        ),
        hasLength(1),
      );
    });

    test('accepts exactly 30 seconds unchanged', () {
      autoDispose(
        createClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.polling,
            pollingInterval: Duration(seconds: 30),
            timeout: shortTimeout,
          ),
        ),
      );

      expect(
        transportOptions.single.pollingInterval,
        const Duration(seconds: 30),
      );
      expect(logger.warnings, isEmpty);
    });

    test('raises a zero interval to 30 seconds without throwing', () {
      expect(
        () => autoDispose(
          createClient(
            connection: const ConnectionOptions(
              mode: ConnectionMode.polling,
              pollingInterval: Duration.zero,
              timeout: shortTimeout,
            ),
          ),
        ),
        returnsNormally,
      );

      expect(
        transportOptions.single.pollingInterval,
        const Duration(seconds: 30),
      );
      expect(logger.warnings.single, contains('below the minimum'));
    });

    test('raises a negative interval to 30 seconds without throwing', () {
      expect(
        () => autoDispose(
          createClient(
            connection: const ConnectionOptions(
              mode: ConnectionMode.polling,
              pollingInterval: Duration(seconds: -5),
              timeout: shortTimeout,
            ),
          ),
        ),
        returnsNormally,
      );

      expect(
        transportOptions.single.pollingInterval,
        const Duration(seconds: 30),
      );
      expect(logger.warnings.single, contains('below the minimum'));
    });

    test('neither throws nor warns about a low interval when streaming', () {
      expect(
        () => autoDispose(
          createClient(
            connection: const ConnectionOptions(
              mode: ConnectionMode.streaming,
              pollingInterval: Duration(seconds: 10),
              timeout: shortTimeout,
            ),
          ),
        ),
        returnsNormally,
      );

      expect(logger.warnings, isEmpty);
    });

    test('the options keep the configured interval', () {
      const connection = ConnectionOptions(
        mode: ConnectionMode.polling,
        pollingInterval: Duration(seconds: 10),
      );

      expect(connection.pollingInterval, const Duration(seconds: 10));
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

    test('tells the transport what prompted each attempt', () async {
      final client = autoDispose(createClient());

      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;
      await client.updateContext(const ConfigDirectorContext(id: 'user-1'));
      client.pauseNetwork();
      await client.resumeNetwork();

      expect(transport.connectCalls.map((call) => call.action), [
        ClientConnectAction.initialization,
        ClientConnectAction.contextUpdate,
        ClientConnectAction.networkResume,
      ]);
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

    test('returns at once when the server rejects the connection', () async {
      transport.connectOutcome = ConnectOutcome.failedFatally;
      final client = autoDispose(
        createClient(
          connection: const ConnectionOptions(
            timeout: Duration(milliseconds: 500),
          ),
        ),
      );
      final contexts = <ConfigDirectorContext?>[];
      client.onContextUpdated.listen((event) => contexts.add(event.context));

      final stopwatch = Stopwatch()..start();
      await client.initialize(const ConfigDirectorContext(id: 'user-1'));
      await pumpEventQueue();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(client.isReady, isFalse);
      expect(client.context, isNull);
      expect(contexts, isEmpty);
      expect(telemetry.contextUpdates, isEmpty);
      expect(logger.warnings, isNot(contains(contains('Timed out'))));
    });
  });

  group('isInitializing', () {
    test('stays true after initialize gives up waiting', () async {
      final client = autoDispose(createClient());

      await client.initialize();

      expect(client.isReady, isFalse);
      expect(client.isInitializing, isTrue);
    });

    test('turns false when the server rejects the connection', () async {
      transport.connectOutcome = ConnectOutcome.failedFatally;
      final client = autoDispose(createClient());

      await client.initialize();

      expect(client.isInitializing, isFalse);
    });

    test('turns false on dispose', () async {
      transport.holdConnects = true;
      final client = createClient();

      final initialization = client.initialize();
      await pumpEventQueue();
      expect(client.isInitializing, isTrue);

      client.dispose();
      transport.heldConnects.single.complete();
      await initialization;

      expect(client.isInitializing, isFalse);
    });

    test('is not set by initialize once config state was received', () async {
      final client = autoDispose(createClient());
      final initialization = client.initialize();
      transport.emitConfigSet(configSet(configs: const {}));
      await initialization;

      final second = client.initialize();
      expect(client.isInitializing, isFalse);
      await second;

      expect(client.isInitializing, isFalse);
    });

    test('is not set by updateContext', () async {
      final client = autoDispose(createClient());

      final update = client.updateContext(
        const ConfigDirectorContext(id: 'user-1'),
      );
      expect(client.isInitializing, isFalse);
      await update;

      expect(client.isInitializing, isFalse);
    });
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

  group('evaluate', () {
    test('says why a config evaluated the way it did', () async {
      final client = autoDispose(createClient());
      final initialization = client.initialize(
        const ConfigDirectorContext(id: 'user-123'),
      );
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
            'max-items': configState('max-items', ConfigType.integer, 'lots'),
          },
        ),
      );
      await initialization;

      final served = client.evaluate('dark-mode', false);
      expect(served.key, 'dark-mode');
      expect(served.value, isTrue);
      expect(served.valueId, 'value-id');
      expect(served.isDefaultValue, isFalse);
      expect(served.reason, EvaluationReason.foundMatch);
      expect(served.context, const ConfigDirectorContext(id: 'user-123'));

      final unreadable = client.evaluate('max-items', 10);
      expect(unreadable.value, 10);
      expect(unreadable.valueId, isNull);
      expect(unreadable.isDefaultValue, isTrue);
      expect(unreadable.reason, EvaluationReason.invalidNumber);

      final unknown = client.evaluate('unknown', 'fallback');
      expect(unknown.value, 'fallback');
      expect(unknown.reason, EvaluationReason.configStateMissing);
      expect(unknown.context, const ConfigDirectorContext(id: 'user-123'));
    });

    test('reports the client not being ready', () {
      final client = autoDispose(createClient());

      final evaluation = client.evaluate('dark-mode', false);

      expect(evaluation.value, isFalse);
      expect(evaluation.isDefaultValue, isTrue);
      expect(evaluation.reason, EvaluationReason.clientNotReady);
    });

    test('is published and counted like getValue', () async {
      final client = autoDispose(createClient());
      final evaluations = <ConfigEvaluation>[];
      client.onConfigEvaluated.listen(
        (event) => evaluations.add(event.evaluation),
      );

      final evaluation = client.evaluate('dark-mode', false);
      await pumpEventQueue();

      expect(evaluations.single.key, 'dark-mode');
      expect(evaluations.single.reason, evaluation.reason);
      expect(telemetry.events.single.key, 'dark-mode');
      expect(telemetry.events.single.requestedType, 'bool');
    });

    test('rejects a function default value', () {
      final client = autoDispose(createClient());

      expect(
        () => client.evaluate('a-key', () {}),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
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
      final updates = <ConfigsUpdatedEvent>[];
      client.onConfigsUpdated.listen(updates.add);

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

      expect(updates.single.keys, ['dark-mode']);
      expect(updates.single.removedKeys, isEmpty);
    });

    test('reports the keys a full set dropped as removed', () async {
      final client = autoDispose(createClient());
      final updates = <ConfigsUpdatedEvent>[];
      client.onConfigsUpdated.listen(updates.add);

      final initialization = client.initialize();
      transport.emitConfigSet(
        configSet(
          configs: {
            'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
            'greeting': configState('greeting', ConfigType.string, 'hello'),
            'max-items': configState('max-items', ConfigType.integer, '25'),
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

      expect(updates, hasLength(2));
      expect(updates[1].keys, ['greeting']);
      expect(updates[1].removedKeys, ['dark-mode', 'max-items']);
    });

    test('reports nothing removed on a delta set', () async {
      final client = autoDispose(createClient());
      final updates = <ConfigsUpdatedEvent>[];
      client.onConfigsUpdated.listen(updates.add);

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
          kind: ConfigSetKind.delta,
        ),
      );
      await pumpEventQueue();

      expect(updates, hasLength(2));
      expect(updates[1].keys, ['greeting']);
      expect(updates[1].removedKeys, isEmpty);
      expect(client.getValue('dark-mode', false), isTrue);
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

  group('invalid context kind', () {
    const userContext = ConfigDirectorContext(id: 'user-123');
    const contextWithAnInvalidContextKind = ConfigDirectorContext(
      id: 'device-42',
      kind: 'Device',
      name: 'Kitchen tablet',
      traits: {'model': 't-1000'},
    );
    late List<Object?> givenContexts;
    late List<StreamController<List<int>>> streams;

    setUp(() {
      givenContexts = [];
      streams = [];
    });

    tearDown(() {
      for (final stream in streams) {
        unawaited(stream.close());
      }
    });

    String configSetBody() => jsonEncode({'kind': 'full', 'configs': {}});

    void recordGivenContext(http.BaseRequest request) {
      final payload =
          jsonDecode((request as http.Request).body) as Map<String, Object?>;
      givenContexts.add(payload['givenContext']);
    }

    DefaultConfigDirectorClient createClientOverHttp(
      ConnectionMode mode,
      http.Client httpClient,
    ) => autoDispose(
      DefaultConfigDirectorClient(
        'a-client-sdk-key',
        options: ConfigDirectorClientOptions(
          logger: logger,
          connection: ConnectionOptions(
            mode: mode,
            timeout: const Duration(seconds: 3),
          ),
        ),
        httpClient: httpClient,
        telemetryClient: telemetry,
        lifecycleWatcher: lifecycleWatcher,
        appInfoResolver: () async => const ConfigDirectorMetaContext(),
        instanceIdStorage: instanceIdStorage,
        connectionRetryDelay: (_) => const Duration(milliseconds: 1),
      ),
    );

    DefaultConfigDirectorClient createStreamingClient() => createClientOverHttp(
      ConnectionMode.streaming,
      MockClient.streaming((request, _) async {
        recordGivenContext(request);
        final stream = StreamController<List<int>>()
          ..add(utf8.encode('data: ${configSetBody()}\n\n'));
        streams.add(stream);
        return http.StreamedResponse(
          stream.stream,
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      }),
    );

    DefaultConfigDirectorClient createPollingClient() => createClientOverHttp(
      ConnectionMode.polling,
      MockClient((request) async {
        recordGivenContext(request);
        return http.Response(configSetBody(), 200);
      }),
    );

    group('over streaming', () {
      test(
        'initialize connects with an empty context and adopts none',
        () async {
          final client = createStreamingClient();
          final contextUpdates = <ConfigDirectorContext?>[];
          client.onContextUpdated.listen(
            (event) => contextUpdates.add(event.context),
          );

          await client.initialize(contextWithAnInvalidContextKind);
          await pumpEventQueue();

          expect(givenContexts, [<String, Object?>{}]);
          expect(client.isReady, isTrue);
          expect(client.context, isNull);
          expect(contextUpdates, [null]);
          expect(logger.errorMessages, hasLength(1));
          expect(logger.errorMessages.single, contains("'Device'"));
        },
      );

      test('updateContext stops using the previous context and connects with '
          'an empty context', () async {
        final client = createStreamingClient();
        await client.initialize(userContext);
        final contextUpdates = <ConfigDirectorContext?>[];
        client.onContextUpdated.listen(
          (event) => contextUpdates.add(event.context),
        );

        await client.updateContext(contextWithAnInvalidContextKind);
        await pumpEventQueue();

        expect(givenContexts, [
          {'id': 'user-123'},
          <String, Object?>{},
        ]);
        expect(client.isReady, isTrue);
        expect(client.context, isNull);
        expect(client.evaluate('dark-mode', false).context, isNull);
        expect(contextUpdates, [null]);
        expect(logger.errorMessages, hasLength(1));
      });

      test('a reconnect counts nothing again', () async {
        final client = createStreamingClient();
        await client.initialize(contextWithAnInvalidContextKind);

        await streams.single.close();
        await Future.doWhile(() async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return givenContexts.length < 2;
        }).timeout(const Duration(seconds: 5));
        await pumpEventQueue();

        expect(givenContexts, [<String, Object?>{}, <String, Object?>{}]);
        expect(telemetry.invalidContextSubmissions, ['Device']);
        expect(logger.errorMessages, hasLength(1));
      });
    });

    group('over polling', () {
      test(
        'initialize connects with an empty context and adopts none',
        () async {
          final client = createPollingClient();
          final contextUpdates = <ConfigDirectorContext?>[];
          client.onContextUpdated.listen(
            (event) => contextUpdates.add(event.context),
          );

          await client.initialize(contextWithAnInvalidContextKind);
          await pumpEventQueue();

          expect(givenContexts, [<String, Object?>{}]);
          expect(client.isReady, isTrue);
          expect(client.context, isNull);
          expect(contextUpdates, [null]);
          expect(logger.errorMessages, hasLength(1));
          expect(logger.errorMessages.single, contains("'Device'"));
        },
      );

      test('updateContext stops using the previous context and connects with '
          'an empty context', () async {
        final client = createPollingClient();
        await client.initialize(userContext);
        final contextUpdates = <ConfigDirectorContext?>[];
        client.onContextUpdated.listen(
          (event) => contextUpdates.add(event.context),
        );

        await client.updateContext(contextWithAnInvalidContextKind);
        await pumpEventQueue();

        expect(givenContexts, [
          {'id': 'user-123'},
          <String, Object?>{},
        ]);
        expect(client.isReady, isTrue);
        expect(client.context, isNull);
        expect(client.evaluate('dark-mode', false).context, isNull);
        expect(contextUpdates, [null]);
        expect(logger.errorMessages, hasLength(1));
      });

      test('a poll counts nothing again', () {
        fakeAsync((async) {
          final client = createPollingClient();

          client.initialize(contextWithAnInvalidContextKind);
          async.elapse(const Duration(seconds: 60));

          expect(givenContexts, [<String, Object?>{}, <String, Object?>{}]);
          expect(telemetry.invalidContextSubmissions, ['Device']);
          expect(logger.errorMessages, hasLength(1));
        });
      });
    });

    test(
      'logs every initialize and updateContext with an invalid context kind',
      () async {
        final client = autoDispose(createClient());

        await client.initialize(contextWithAnInvalidContextKind);
        await client.updateContext(contextWithAnInvalidContextKind);
        await client.updateContext(contextWithAnInvalidContextKind);

        expect(logger.errorMessages, hasLength(3));
      },
    );

    test(
      'logs the first 128 characters of a long invalid context kind',
      () async {
        final client = autoDispose(createClient());

        await client.initialize(
          ConfigDirectorContext(id: 'device-42', kind: 'D' * 200),
        );

        expect(logger.errorMessages.single, contains('D' * 128));
        expect(logger.errorMessages.single, isNot(contains('D' * 129)));
      },
    );

    test('resuming the network reconnects with no context', () async {
      final client = autoDispose(createClient());
      await client.initialize(userContext);
      await client.updateContext(contextWithAnInvalidContextKind);

      client.pauseNetwork();
      await client.resumeNetwork();

      expect(transport.connectCalls.map((call) => call.context), [
        userContext,
        const ConfigDirectorContext(),
        const ConfigDirectorContext(),
      ]);
      expect(client.context, isNull);
    });

    test(
      'keeps the previous context when the server rejects the connection',
      () async {
        final client = autoDispose(createClient());
        await client.initialize(userContext);
        transport.connectOutcome = ConnectOutcome.failedFatally;

        await client.updateContext(contextWithAnInvalidContextKind);

        expect(
          transport.connectCalls.last.context,
          const ConfigDirectorContext(),
        );
        expect(client.context, userContext);
      },
    );

    test(
      'counts one invalid context submission per initialize or updateContext',
      () async {
        final client = autoDispose(createClient());

        await client.initialize(contextWithAnInvalidContextKind);
        await client.updateContext(
          const ConfigDirectorContext(id: 'tenant-7', kind: 'Tenant'),
        );

        expect(telemetry.invalidContextSubmissions, ['Device', 'Tenant']);
      },
    );

    test(
      'counts the first 128 characters of a long invalid context kind',
      () async {
        final client = autoDispose(createClient());

        await client.initialize(
          ConfigDirectorContext(id: 'device-42', kind: 'D' * 200),
        );

        expect(telemetry.invalidContextSubmissions, ['D' * 128]);
      },
    );

    test('counts nothing again when configs are read', () async {
      final client = autoDispose(createClient());
      await client.initialize(contextWithAnInvalidContextKind);

      client
        ..getValue('dark-mode', false)
        ..evaluate('dark-mode', false);

      expect(telemetry.invalidContextSubmissions, ['Device']);
    });

    test('counts nothing again when the network resumes', () async {
      final client = autoDispose(createClient());
      await client.initialize(contextWithAnInvalidContextKind);

      client.pauseNetwork();
      await client.resumeNetwork();

      expect(telemetry.invalidContextSubmissions, ['Device']);
    });

    test('never hands the ignored context to telemetry', () async {
      final client = autoDispose(createClient());

      await client.initialize(contextWithAnInvalidContextKind);

      expect(telemetry.contextUpdates, [null]);
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

  group('offline mode', () {
    late List<http.BaseRequest> httpRequests;
    late int appInfoReads;

    setUp(() {
      httpRequests = [];
      appInfoReads = 0;
    });

    DefaultConfigDirectorClient createOfflineClient({
      String? clientSdkKey,
      ConnectionOptions connection = const ConnectionOptions(
        mode: ConnectionMode.offline,
      ),
    }) => autoDispose(
      DefaultConfigDirectorClient(
        clientSdkKey,
        options: ConfigDirectorClientOptions(
          logger: logger,
          connection: connection,
        ),
        httpClient: MockClient((request) async {
          httpRequests.add(request);
          return http.Response('', 500);
        }),
        telemetryClient: telemetry,
        transportFactory: (options) {
          transportOptions.add(options);
          return transport;
        },
        lifecycleWatcher: lifecycleWatcher,
        appInfoResolver: () async {
          appInfoReads += 1;
          return const ConfigDirectorMetaContext();
        },
        instanceIdStorage: instanceIdStorage,
      ),
    );

    test('accepts a missing client SDK key', () {
      expect(createOfflineClient, returnsNormally);
    });

    test('accepts an empty client SDK key', () {
      expect(() => createOfflineClient(clientSdkKey: ''), returnsNormally);
    });

    test('serves the in-code default value of every config when given no '
        'values', () async {
      final client = createOfflineClient();

      await client.initialize();

      final evaluation = client.evaluate('new-checkout', false);
      expect(client.isReady, isTrue);
      expect(evaluation.value, isFalse);
      expect(evaluation.reason, EvaluationReason.configStateMissing);
    });

    test('serves an inline value with the found-match reason', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'max-items': 20},
        ),
      );

      await client.initialize();

      final evaluation = client.evaluate('max-items', 0);
      expect(evaluation.value, 20);
      expect(evaluation.reason, EvaluationReason.foundMatch);
    });

    test('rejects initialization for a null value', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': null},
        ),
      );

      await expectLater(
        client.initialize(),
        throwsA(isA<ConfigDirectorInitializationException>()),
      );

      expect(client.isReady, isFalse);
      expect(client.isInitializing, isFalse);
    });

    test('rejects initialization for a value of an unsupported type', () async {
      final client = createOfflineClient(
        connection: ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'launch-date': DateTime(2026)},
        ),
      );

      await expectLater(
        client.initialize(),
        throwsA(isA<ConfigDirectorInitializationException>()),
      );

      expect(client.isReady, isFalse);
    });

    test('rejects initialization when values are given in streaming '
        'mode', () async {
      final client = autoDispose(
        createClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.streaming,
            values: {'new-checkout': true},
            timeout: Duration(milliseconds: 50),
          ),
        ),
      );

      await expectLater(
        client.initialize(),
        throwsA(isA<ConfigDirectorInitializationException>()),
      );

      expect(client.isReady, isFalse);
      expect(transport.connectCalls, isEmpty);
    });

    test('rejects initialization when values are given in polling '
        'mode', () async {
      final client = autoDispose(
        createClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.polling,
            values: {'new-checkout': true},
            timeout: Duration(milliseconds: 50),
          ),
        ),
      );

      await expectLater(
        client.initialize(),
        throwsA(isA<ConfigDirectorInitializationException>()),
      );

      expect(client.isReady, isFalse);
      expect(transport.connectCalls, isEmpty);
    });

    test('becomes ready at once and fires the ready and configs updated '
        'events once', () {
      fakeAsync((async) {
        final client = createOfflineClient(
          connection: const ConnectionOptions(
            mode: ConnectionMode.offline,
            values: {'new-checkout': true},
          ),
        );
        final readyEvents = <ClientReadyEvent>[];
        final configsUpdates = <ConfigsUpdatedEvent>[];
        client.onClientReady.listen(readyEvents.add);
        client.onConfigsUpdated.listen(configsUpdates.add);

        var initialized = false;
        client.initialize().then((_) => initialized = true);
        async.flushMicrotasks();

        expect(initialized, isTrue);
        expect(client.isReady, isTrue);
        expect(readyEvents.single.action, ClientConnectAction.initialization);
        expect(configsUpdates.single.keys, ['new-checkout']);
      });
    });

    test('emits the context update before the ready event', () async {
      final client = createOfflineClient();
      final events = <Object>[];
      client.onContextUpdated.listen(events.add);
      client.onClientReady.listen(events.add);

      await client.initialize(ConfigDirectorContext(id: 'user-1'));
      await pumpEventQueue();

      expect(events, [isA<ContextUpdatedEvent>(), isA<ClientReadyEvent>()]);
    });

    test('updateContext takes the new context at once and changes no '
        'value', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );
      await client.initialize(ConfigDirectorContext(id: 'user-1'));
      final contextUpdates = <ContextUpdatedEvent>[];
      final readyEvents = <ClientReadyEvent>[];
      final configsUpdates = <ConfigsUpdatedEvent>[];
      client.onContextUpdated.listen(contextUpdates.add);
      client.onClientReady.listen(readyEvents.add);
      client.onConfigsUpdated.listen(configsUpdates.add);
      final newContext = ConfigDirectorContext(id: 'user-2');

      await client.updateContext(newContext);
      await pumpEventQueue();

      expect(client.context, newContext);
      expect(contextUpdates.single.context, newContext);
      expect(client.isReady, isTrue);
      expect(client.getValue('new-checkout', false), isTrue);
      expect(readyEvents, isEmpty);
      expect(configsUpdates, isEmpty);
    });

    test('keeps the context of an updateContext called while initialize is '
        'pending', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );
      final newContext = ConfigDirectorContext(id: 'user-2');

      final initialization = client.initialize(
        ConfigDirectorContext(id: 'user-1'),
      );
      await client.updateContext(newContext);
      await initialization;
      await pumpEventQueue();

      expect(client.context, newContext);
      expect(client.isReady, isTrue);
    });

    test('pauseNetwork and resumeNetwork do nothing', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );
      await client.initialize();
      final readyEvents = <ClientReadyEvent>[];
      client.onClientReady.listen(readyEvents.add);

      client.pauseNetwork();
      final readyWhilePaused = client.isReady;
      await client.resumeNetwork();
      await pumpEventQueue();

      expect(readyWhilePaused, isTrue);
      expect(client.getValue('new-checkout', false), isTrue);
      expect(readyEvents, isEmpty);
    });

    test('sends no telemetry', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );
      await client.initialize(ConfigDirectorContext(id: 'user-1'));
      client.getValue('new-checkout', false);
      await client.updateContext(ConfigDirectorContext(id: 'user-2'));

      client.dispose();

      expect(telemetry.events, isEmpty);
      expect(telemetry.contextUpdates, isEmpty);
      expect(telemetry.closeCount, 0);
    });

    test('does not follow the app lifecycle', () {
      createOfflineClient();

      expect(lifecycleWatcher.isStarted, isFalse);
    });

    test('serves the in-code default value for a value of another '
        'type', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );

      await client.initialize();

      final evaluation = client.evaluate('new-checkout', 'off');
      expect(evaluation.value, 'off');
      expect(evaluation.reason, EvaluationReason.typeMismatch);
    });

    test('watch emits the offline value once', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );
      await client.initialize();
      final emitted = <bool>[];
      client.watch('new-checkout', false).listen(emitted.add);
      await pumpEventQueue();

      await client.updateContext(ConfigDirectorContext(id: 'user-2'));
      client.pauseNetwork();
      await client.resumeNetwork();
      await pumpEventQueue();

      expect(emitted, [true]);
    });

    test('opens no connection', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          values: {'new-checkout': true},
        ),
      );

      await client.initialize(ConfigDirectorContext(id: 'user-1'));
      await client.updateContext(ConfigDirectorContext(id: 'user-2'));
      client.pauseNetwork();
      await client.resumeNetwork();
      await pumpEventQueue();

      expect(httpRequests, isEmpty);
      expect(transport.connectCalls, isEmpty);
    });

    test('reads nothing from the platform', () async {
      final client = createOfflineClient();

      await client.initialize();

      expect(appInfoReads, 0);
      expect(instanceIdStorage.readCount, 0);
      expect(instanceIdStorage.writes, isEmpty);
    });

    test('updateContext ignores a context with an invalid context '
        'kind', () async {
      final client = createOfflineClient();
      await client.initialize(ConfigDirectorContext(id: 'user-1'));

      await client.updateContext(
        ConfigDirectorContext(id: 'device-1', kind: 'Not Valid'),
      );

      expect(client.context, isNull);
    });

    test('ignores the timeout', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          timeout: Duration.zero,
        ),
      );

      await client.initialize();

      expect(client.isReady, isTrue);
    });

    test('ignores the base URL', () async {
      final client = createOfflineClient(
        connection: ConnectionOptions(
          mode: ConnectionMode.offline,
          baseUrl: Uri.parse('/proxy'),
        ),
      );

      await client.initialize();

      expect(client.isReady, isTrue);
    });

    test('ignores the polling interval', () async {
      final client = createOfflineClient(
        connection: const ConnectionOptions(
          mode: ConnectionMode.offline,
          pollingInterval: Duration.zero,
        ),
      );

      await client.initialize();

      expect(client.isReady, isTrue);
      expect(logger.warnings, isEmpty);
    });
  });
}

/// Registers [client] for disposal at the end of the test and returns it.
DefaultConfigDirectorClient autoDispose(DefaultConfigDirectorClient client) {
  addTearDown(client.dispose);
  return client;
}
