import 'dart:async';
import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/src/transport/polling_transport.dart';
import 'package:configdirector_flutter_client_sdk/src/transport/transport.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const Duration _timeout = Duration(seconds: 3);

String configSetBody({
  Map<String, Object?> configs = const {},
  String kind = 'full',
  String? timestamp,
}) => jsonEncode({
  'environmentId': 'env-id',
  'projectId': 'project-id',
  'kind': kind,
  if (timestamp != null) 'timestamp': timestamp,
  'configs': configs,
});

Map<String, Object?> configJson(String key, String type, String value) => {
  'id': '$key-id',
  'key': key,
  'type': type,
  'value': value,
  'valueId': 'value-id',
};

void main() {
  late RecordingLogger logger;
  late List<http.Request> requests;

  setUp(() {
    logger = RecordingLogger();
    requests = [];
  });

  TransportOptions optionsWith(
    http.Client client, {
    Duration? pollingInterval,
  }) => TransportOptions(
    clientSdkKey: 'a-client-sdk-key',
    baseUrl: Uri.parse('https://sdk.example.com'),
    metaContext: const SdkMetaContext(
      sdkName: 'flutter-client-sdk',
      sdkVersion: '0.0.1',
      metadata: ConfigDirectorMetaContext(
        appName: 'test-app',
        appVersion: '1.2.3',
      ),
    ),
    instanceId: 'instance-id',
    logger: logger,
    connectionRetryDelay: (_) => Duration.zero,
    httpClient: client,
    pollingInterval: pollingInterval,
  );

  MockClient respondWith(List<http.Response> responses) {
    var index = 0;
    return MockClient((request) async {
      requests.add(request);
      return responses[index++ < responses.length
          ? index - 1
          : responses.length - 1];
    });
  }

  test('posts the payload to the polling endpoint', () async {
    final transport = PollingTransport(
      optionsWith(respondWith([http.Response(configSetBody(), 200)])),
    );
    addTearDown(transport.dispose);

    await transport.connect(
      const ConfigDirectorContext(id: 'user-1', name: 'Ada'),
      _timeout,
    );

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url, Uri.parse('https://sdk.example.com/client/polling/v1'));
    expect(jsonDecode(request.body), {
      'givenContext': {'id': 'user-1', 'name': 'Ada'},
      'metaContext': {
        'appName': 'test-app',
        'appVersion': '1.2.3',
        'sdkName': 'flutter-client-sdk',
        'sdkVersion': '0.0.1',
      },
      'clientSdkKey': 'a-client-sdk-key',
      'instanceId': 'instance-id',
    });
  });

  test('emits the config set it receives', () async {
    final transport = PollingTransport(
      optionsWith(
        respondWith([
          http.Response(
            configSetBody(
              configs: {
                'dark-mode': configJson('dark-mode', 'boolean', 'true'),
              },
            ),
            200,
          ),
        ]),
      ),
    );
    addTearDown(transport.dispose);

    final received = transport.configSets.first;
    await transport.connect(const ConfigDirectorContext(), _timeout);

    final configSet = await received;
    expect(configSet.kind, ConfigSetKind.full);
    expect(configSet.configs['dark-mode']?.value, 'true');
    expect(configSet.configs['dark-mode']?.type, ConfigType.boolean);
  });

  test('echoes the last timestamp back on the next poll', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          respondWith([
            http.Response(
              configSetBody(timestamp: '2026-08-02T00:00:00Z'),
              200,
            ),
          ]),
          pollingInterval: const Duration(seconds: 30),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
      async.elapse(const Duration(seconds: 31));

      expect(requests.length, 2);
      expect(
        jsonDecode(requests.first.body),
        isNot(contains('lastUpdateTimestamp')),
      );
      expect(
        (jsonDecode(requests.last.body) as Map)['lastUpdateTimestamp'],
        '2026-08-02T00:00:00Z',
      );
    });
  });

  test('keeps polling on the configured interval', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          respondWith([http.Response(configSetBody(), 200)]),
          pollingInterval: const Duration(seconds: 10),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
      async.elapse(const Duration(seconds: 35));

      expect(requests.length, 4);
    });
  });

  test('stops polling once closed', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          respondWith([http.Response(configSetBody(), 200)]),
          pollingInterval: const Duration(seconds: 10),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
      async.elapse(const Duration(seconds: 15));
      transport.close();
      async.elapse(const Duration(seconds: 60));

      expect(requests.length, 2);
    });
  });

  test('a connect overtaken by a newer one does not keep polling', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          MockClient((request) async {
            requests.add(request);
            if (request.body.contains('"id":"user-1"')) {
              await Future<void>.delayed(const Duration(seconds: 2));
            }
            return http.Response(configSetBody(), 200);
          }),
          pollingInterval: const Duration(seconds: 10),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(
        transport.connect(const ConfigDirectorContext(id: 'user-1'), _timeout),
      );
      unawaited(
        transport.connect(const ConfigDirectorContext(id: 'user-2'), _timeout),
      );
      async.elapse(const Duration(seconds: 25));

      final polled = requests.skip(2).map((request) => request.body);
      expect(polled, hasLength(2));
      expect(polled, everyElement(contains('"id":"user-2"')));
    });
  });

  test('does not start polling when closed while connecting', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          MockClient((request) async {
            requests.add(request);
            await Future<void>.delayed(const Duration(seconds: 1));
            return http.Response(configSetBody(), 200);
          }),
          pollingInterval: const Duration(seconds: 10),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
      transport.close();
      async.elapse(const Duration(seconds: 35));

      expect(requests, hasLength(1));
    });
  });

  test('keeps polling after a transient failure so the client can recover', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          respondWith([
            http.Response('server exploded', 500),
            http.Response(configSetBody(), 200),
          ]),
          pollingInterval: const Duration(seconds: 10),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
      async.elapse(const Duration(seconds: 11));

      expect(
        logger.messages,
        contains(contains('The initial fetch failed, will keep polling')),
      );
      expect(requests.length, 2);
    });
  });

  test('stops polling after an unrecoverable failure', () {
    fakeAsync((async) {
      final transport = PollingTransport(
        optionsWith(
          respondWith([http.Response('invalid sdk key', 401)]),
          pollingInterval: const Duration(seconds: 10),
        ),
      );
      addTearDown(transport.dispose);

      unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
      async.elapse(const Duration(seconds: 60));

      expect(
        logger.messages,
        contains(contains('unrecoverable error, will not poll')),
      );
      expect(logger.errors, contains(contains('invalid sdk key')));
      expect(requests.length, 1);
    });
  });

  test('ignores reconnect attempts after an unrecoverable failure', () async {
    final transport = PollingTransport(
      optionsWith(respondWith([http.Response('invalid sdk key', 403)])),
    );
    addTearDown(transport.dispose);

    await transport.connect(const ConfigDirectorContext(), _timeout);
    await transport.connect(const ConfigDirectorContext(), _timeout);

    expect(requests.length, 1);
    expect(
      logger.messages.any(
        (message) => message.contains('prior unrecoverable error'),
      ),
      isTrue,
    );
  });

  test('logs a malformed response body', () async {
    final transport = PollingTransport(
      optionsWith(respondWith([http.Response('not json', 200)])),
    );
    addTearDown(transport.dispose);

    await transport.connect(const ConfigDirectorContext(), _timeout);

    expect(logger.messages, contains(contains('will keep polling')));
    expect(logger.errors, contains(contains('Failed to parse the response')));
  });

  test('logs a response whose fields have the wrong types', () async {
    final transport = PollingTransport(
      optionsWith(
        respondWith([
          http.Response(
            configSetBody(
              configs: {
                'dark-mode': {'id': 1, 'key': 'dark-mode', 'type': 'boolean'},
              },
            ),
            200,
          ),
        ]),
      ),
    );
    addTearDown(transport.dispose);

    await transport.connect(const ConfigDirectorContext(), _timeout);

    expect(logger.errors, contains(contains('unexpected payload')));
  });

  test('logs a timed out request', () async {
    final transport = PollingTransport(
      optionsWith(
        MockClient((request) async {
          requests.add(request);
          await Future<void>.delayed(const Duration(seconds: 1));
          return http.Response(configSetBody(), 200);
        }),
      ),
    );
    addTearDown(transport.dispose);

    await transport.connect(
      const ConfigDirectorContext(),
      const Duration(milliseconds: 20),
    );

    expect(logger.errors, contains(contains('timed out')));
  });

  test('ignores a 204 response', () async {
    final transport = PollingTransport(
      optionsWith(respondWith([http.Response('', 204)])),
    );
    addTearDown(transport.dispose);

    final configSets = <ConfigSet>[];
    transport.configSets.listen(configSets.add);
    await transport.connect(const ConfigDirectorContext(), _timeout);
    await pumpEventQueue();

    expect(configSets, isEmpty);
  });

  group('OneTimeTransport', () {
    test('fetches once and never polls', () {
      fakeAsync((async) {
        final transport = OneTimeTransport(
          optionsWith(
            respondWith([http.Response(configSetBody(), 200)]),
            pollingInterval: const Duration(seconds: 10),
          ),
        );
        addTearDown(transport.dispose);

        unawaited(transport.connect(const ConfigDirectorContext(), _timeout));
        async.elapse(const Duration(minutes: 10));

        expect(requests.length, 1);
      });
    });

    test('fetches again on a context update', () async {
      final transport = OneTimeTransport(
        optionsWith(respondWith([http.Response(configSetBody(), 200)])),
      );
      addTearDown(transport.dispose);

      await transport.connect(
        const ConfigDirectorContext(id: 'user-1'),
        _timeout,
      );
      await transport.connect(
        const ConfigDirectorContext(id: 'user-2'),
        _timeout,
      );

      expect(requests.length, 2);
      expect((jsonDecode(requests.last.body) as Map)['givenContext'], {
        'id': 'user-2',
      });
    });
  });
}
