@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/src/client/default_config_director_client.dart';
import 'package:configdirector_flutter_client_sdk/src/client_session.dart';
import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
import 'package:configdirector_flutter_client_sdk/src/platform/app_info.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Exercises the client with the telemetry it builds for itself, all the way
/// through the telemetry isolate and out to a server.
void main() {
  late HttpServer server;
  late FakeTransport transport;
  late FakeLifecycleWatcher lifecycleWatcher;
  late RecordingLogger logger;
  late Completer<Map<String, Object?>> reported;

  setUp(() async {
    transport = FakeTransport();
    lifecycleWatcher = FakeLifecycleWatcher();
    logger = RecordingLogger();
    reported = Completer<Map<String, Object?>>();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        if (!reported.isCompleted) {
          reported.complete(
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>,
          );
        }
        request.response.statusCode = 202;
        await request.response.close();
      }),
    );
  });

  tearDown(() => server.close(force: true));

  DefaultConfigDirectorClient createClient({
    required AppInfoResolver appInfoResolver,
    InstanceIdStorage? instanceIdStorage,
    ClientSession? clientSession,
  }) {
    final client = DefaultConfigDirectorClient(
      'a-client-sdk-key',
      options: ConfigDirectorClientOptions(
        logger: logger,
        connection: ConnectionOptions(
          baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
          timeout: const Duration(milliseconds: 50),
        ),
      ),
      transportFactory: (_) => transport,
      lifecycleWatcher: lifecycleWatcher,
      userAgentResolver: () => 'integration-tests',
      appInfoResolver: appInfoResolver,
      instanceIdStorage: instanceIdStorage,
      clientSession: clientSession,
    );
    addTearDown(client.dispose);
    return client;
  }

  test('reports the configs an application evaluated', () async {
    final client = createClient(
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
    );

    final initialization = client.initialize(
      const ConfigDirectorContext(id: 'user-123'),
    );
    transport.emitConfigSet(
      configSet(
        configs: {
          'dark-mode': configState('dark-mode', ConfigType.boolean, 'true'),
        },
      ),
    );
    await initialization;

    client
      ..getValue('dark-mode', false)
      ..getValue('dark-mode', false);
    // Backgrounding the app reports what has been collected without waiting for
    // the flush interval.
    lifecycleWatcher.send(AppLifecycleState.hidden);

    final report = await reported.future.timeout(const Duration(seconds: 10));

    expect(report['clientSdkKey'], 'a-client-sdk-key');
    expect(report['context'], {'id': 'user-123'});
    expect(report['metaContext'], {
      'sdkName': constants.sdkName,
      'sdkVersion': constants.sdkVersion,
      'userAgent': 'integration-tests',
    });
    expect(report['droppedEvents'], {'evaluatedConfig': 0});

    final aggregated =
        (report['aggregatedEvents']!
                as Map<String, Object?>)['evaluatedConfig']!
            as List<Object?>;
    expect(aggregated.single, {
      'startTime': isA<String>(),
      'endTime': isA<String>(),
      'count': 2,
      'event': {
        'contextId': 'user-123',
        'key': 'dark-mode',
        'type': 'boolean',
        'defaultValue': {'value': 'false'},
        'requestedType': 'bool',
        'evaluatedValue': {'value': 'true'},
        'evaluatedValueId': 'value-id',
        'usedDefault': false,
        'evaluationReason': 'found-match',
      },
    });
  });

  test('reports a context ignored for its invalid context kind without the '
      'context', () async {
    final client = createClient(
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
    );

    final initialization = client.initialize(
      const ConfigDirectorContext(
        id: 'device-42',
        kind: 'Device',
        name: 'Kitchen tablet',
        traits: {'model': 't-1000'},
      ),
    );
    transport.emitConfigSet(configSet(configs: const {}));
    await initialization;
    lifecycleWatcher.send(AppLifecycleState.hidden);

    final report = await reported.future.timeout(const Duration(seconds: 10));

    expect(
      (report['aggregatedEvents']! as Map<String, Object?>)['invalidContext'],
      [
        {
          'startTime': isA<String>(),
          'endTime': isA<String>(),
          'count': 1,
          'event': {'reason': 'invalid-context-kind', 'kindSample': 'Device'},
        },
      ],
    );
    expect(report, isNot(contains('context')));
    expect(jsonEncode(report), isNot(contains('device-42')));
    expect(jsonEncode(report), isNot(contains('Kitchen tablet')));
    expect(jsonEncode(report), isNot(contains('t-1000')));
  });

  test('reports the app name and version read from the platform', () async {
    final client = createClient(
      appInfoResolver: () async => const ConfigDirectorMetaContext(
        appName: 'Sample App',
        appVersion: '4.5.6',
      ),
    );

    final initialization = client.initialize();
    transport.emitConfigSet(configSet(configs: const {}));
    await initialization;

    client.getValue('dark-mode', false);
    lifecycleWatcher.send(AppLifecycleState.hidden);

    final report = await reported.future.timeout(const Duration(seconds: 10));

    expect(report['metaContext'], containsPair('appName', 'Sample App'));
    expect(report['metaContext'], containsPair('appVersion', '4.5.6'));
  });

  test('reports the instance ID read from storage', () async {
    final client = createClient(
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
      instanceIdStorage: FakeInstanceIdStorage()
        ..record = jsonEncode({
          'v': 1,
          'id': '3f2b8c1e-7a4d-4e9b-8c6f-1d2e3f4a5b6c',
          'createdAt': DateTime.now().millisecondsSinceEpoch - 60000,
        }),
    );

    final initialization = client.initialize();
    transport.emitConfigSet(configSet(configs: const {}));
    await initialization;

    client.getValue('dark-mode', false);
    lifecycleWatcher.send(AppLifecycleState.hidden);

    final report = await reported.future.timeout(const Duration(seconds: 10));

    expect(report['instanceId'], '3f2b8c1e-7a4d-4e9b-8c6f-1d2e3f4a5b6c');
  });

  test('reports an ephemeral instance ID without the ephemeral flag', () async {
    final client = createClient(
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
      clientSession: const ClientSession(
        instanceId: '9d8c7b6a-5f4e-4d3c-a2b1-0f9e8d7c6b5a',
        ephemeral: true,
      ),
    );

    final initialization = client.initialize();
    transport.emitConfigSet(configSet(configs: const {}));
    await initialization;

    client.getValue('dark-mode', false);
    lifecycleWatcher.send(AppLifecycleState.hidden);

    final report = await reported.future.timeout(const Duration(seconds: 10));

    expect(report['instanceId'], '9d8c7b6a-5f4e-4d3c-a2b1-0f9e8d7c6b5a');
    expect(report, isNot(contains('ephemeral')));
  });
}
