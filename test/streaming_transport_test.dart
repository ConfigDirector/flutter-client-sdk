import 'dart:async';
import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/src/transport/streaming_transport.dart';
import 'package:configdirector_flutter_client_sdk/src/transport/transport.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const Duration _timeout = Duration(seconds: 3);

void main() {
  late RecordingLogger logger;
  late List<http.BaseRequest> requests;
  late List<StreamController<List<int>>> bodies;
  late List<Duration> requestedRetryDelays;

  setUp(() {
    logger = RecordingLogger();
    requests = [];
    bodies = [];
    requestedRetryDelays = [];
  });

  tearDown(() {
    for (final body in bodies) {
      if (!body.isClosed) {
        unawaited(body.close());
      }
    }
  });

  TransportOptions optionsWith(http.Client client) => TransportOptions(
    clientSdkKey: 'a-client-sdk-key',
    baseUrl: Uri.parse('https://sdk.example.com'),
    metaContext: const SdkMetaContext(
      sdkName: 'flutter-client-sdk',
      sdkVersion: '0.0.1',
    ),
    instanceId: 'instance-id',
    logger: logger,
    connectionRetryDelay: (attempt) {
      final delay = Duration(milliseconds: attempt);
      requestedRetryDelays.add(delay);
      return delay;
    },
    httpClient: client,
  );

  /// A client that opens a server-sent events stream the test can write to.
  MockClient streamingClient({int status = 200}) =>
      MockClient.streaming((request, _) async {
        requests.add(request);
        final body = StreamController<List<int>>();
        bodies.add(body);
        return http.StreamedResponse(
          body.stream,
          status,
          headers: const {'content-type': 'text/event-stream'},
        );
      });

  void sendEvent(String data) =>
      bodies.last.add(utf8.encode('data: $data\n\n'));

  String configSetBody({
    Map<String, Object?> configs = const {},
    String kind = 'full',
  }) => jsonEncode({
    'environmentId': 'env-id',
    'projectId': 'project-id',
    'kind': kind,
    'configs': configs,
  });

  test('opens a stream against the SSE endpoint with the payload', () async {
    final transport = StreamingTransport(optionsWith(streamingClient()));
    addTearDown(transport.dispose);

    await transport.connect(
      const ConfigDirectorContext(id: 'user-1'),
      _timeout,
    );

    final request = requests.single as http.Request;
    expect(request.method, 'POST');
    expect(request.url, Uri.parse('https://sdk.example.com/client/sse/v1'));
    expect(request.headers['Accept'], 'text/event-stream');
    expect(jsonDecode(request.body), {
      'givenContext': {'id': 'user-1'},
      'metaContext': {'sdkName': 'flutter-client-sdk', 'sdkVersion': '0.0.1'},
      'clientSdkKey': 'a-client-sdk-key',
      'instanceId': 'instance-id',
    });
  });

  test('emits a config set for every message received', () async {
    final transport = StreamingTransport(optionsWith(streamingClient()));
    addTearDown(transport.dispose);

    final configSets = <ConfigSet>[];
    transport.configSets.listen(configSets.add);
    await transport.connect(const ConfigDirectorContext(), _timeout);

    sendEvent(
      configSetBody(
        configs: {
          'dark-mode': {
            'id': 'dark-mode-id',
            'key': 'dark-mode',
            'type': 'boolean',
            'value': 'true',
            'valueId': 'value-id',
          },
        },
      ),
    );
    sendEvent(configSetBody(kind: 'delta'));
    await pumpEventQueue();

    expect(configSets.length, 2);
    expect(configSets.first.configs['dark-mode']?.value, 'true');
    expect(configSets.last.kind, ConfigSetKind.delta);
  });

  test(
    'logs and skips a malformed message instead of failing the stream',
    () async {
      final transport = StreamingTransport(optionsWith(streamingClient()));
      addTearDown(transport.dispose);

      final configSets = <ConfigSet>[];
      transport.configSets.listen(configSets.add);
      await transport.connect(const ConfigDirectorContext(), _timeout);

      sendEvent('not json');
      sendEvent(configSetBody());
      await pumpEventQueue();

      expect(configSets.length, 1);
      expect(
        logger.messages.any(
          (message) => message.contains('Error parsing and dispatching'),
        ),
        isTrue,
      );
    },
  );

  test('logs and skips a message that is not a JSON object', () async {
    final transport = StreamingTransport(optionsWith(streamingClient()));
    addTearDown(transport.dispose);

    final configSets = <ConfigSet>[];
    transport.configSets.listen(configSets.add);
    await transport.connect(const ConfigDirectorContext(), _timeout);

    sendEvent('[1, 2, 3]');
    sendEvent(configSetBody());
    await pumpEventQueue();

    expect(configSets.length, 1);
    expect(logger.messages, contains(contains('not a JSON object')));
  });

  test('logs and skips a message whose fields have the wrong types', () async {
    final transport = StreamingTransport(optionsWith(streamingClient()));
    addTearDown(transport.dispose);

    final configSets = <ConfigSet>[];
    transport.configSets.listen(configSets.add);
    await transport.connect(const ConfigDirectorContext(), _timeout);

    sendEvent(
      configSetBody(
        configs: {
          'dark-mode': {'id': 1, 'key': 'dark-mode', 'type': 'boolean'},
        },
      ),
    );
    sendEvent(configSetBody());
    await pumpEventQueue();

    expect(configSets.length, 1);
    expect(
      logger.messages.any(
        (message) => message.contains('Error parsing and dispatching'),
      ),
      isTrue,
    );
  });

  test(
    'logs an unrecoverable error when the server rejects the request',
    () async {
      final transport = StreamingTransport(
        optionsWith(streamingClient(status: 401)),
      );
      addTearDown(transport.dispose);

      await transport.connect(const ConfigDirectorContext(), _timeout);

      expect(
        logger.messages,
        contains(
          allOf(
            contains('status: 401'),
            contains('will not attempt to reconnect'),
          ),
        ),
      );
      expect(requestedRetryDelays, isEmpty);
    },
  );

  test('retries after a recoverable failure', () async {
    var attempts = 0;
    final client = MockClient.streaming((request, _) async {
      requests.add(request);
      attempts++;
      if (attempts == 1) {
        return http.StreamedResponse(const Stream<List<int>>.empty(), 503);
      }
      final body = StreamController<List<int>>();
      bodies.add(body);
      return http.StreamedResponse(body.stream, 200);
    });
    final transport = StreamingTransport(optionsWith(client));
    addTearDown(transport.dispose);

    await transport.connect(const ConfigDirectorContext(), _timeout);

    expect(attempts, 2);
    expect(requestedRetryDelays, [const Duration(milliseconds: 1)]);
  });

  test('returns once the timeout elapses without failing', () async {
    final client = MockClient.streaming((request, _) {
      requests.add(request);
      return Completer<http.StreamedResponse>().future;
    });
    final transport = StreamingTransport(optionsWith(client));
    addTearDown(transport.dispose);

    await expectLater(
      transport.connect(
        const ConfigDirectorContext(),
        const Duration(milliseconds: 20),
      ),
      completes,
    );
  });

  test('reconnecting replaces the previous stream', () async {
    final transport = StreamingTransport(optionsWith(streamingClient()));
    addTearDown(transport.dispose);

    final configSets = <ConfigSet>[];
    transport.configSets.listen(configSets.add);
    await transport.connect(
      const ConfigDirectorContext(id: 'user-1'),
      _timeout,
    );
    final firstBody = bodies.last;

    await transport.connect(
      const ConfigDirectorContext(id: 'user-2'),
      _timeout,
    );
    firstBody.add(utf8.encode('data: ${configSetBody()}\n\n'));
    sendEvent(configSetBody());
    await pumpEventQueue();

    expect(requests.length, 2);
    expect(configSets.length, 1);
  });

  test(
    'close stops the connection but leaves the transport reusable',
    () async {
      final transport = StreamingTransport(optionsWith(streamingClient()));
      addTearDown(transport.dispose);

      await transport.connect(const ConfigDirectorContext(), _timeout);
      transport.close();

      final configSets = <ConfigSet>[];
      transport.configSets.listen(configSets.add);
      sendEvent(configSetBody());
      await pumpEventQueue();
      expect(configSets, isEmpty);

      await transport.connect(const ConfigDirectorContext(), _timeout);
      sendEvent(configSetBody());
      await pumpEventQueue();

      expect(configSets.length, 1);
    },
  );
}
