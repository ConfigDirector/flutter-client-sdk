@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/src/client/default_config_director_client.dart';
import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
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

  test('reports the configs an application evaluated', () async {
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
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
    );
    addTearDown(client.dispose);

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
}
