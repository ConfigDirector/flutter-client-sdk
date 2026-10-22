@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late List<Uri> requestedUrls;

  setUp(() async {
    requestedUrls = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        requestedUrls.add(request.uri);
        request.response.statusCode = 500;
        await request.response.close();
      }),
    );
  });

  tearDown(() => server.close(force: true));

  test('an offline client sends no request, for configs or for '
      'telemetry', () async {
    final httpClients = <_RecordingHttpClient>[];

    await HttpOverrides.runZoned(() async {
      final client = ConfigDirectorClient(
        options: ConfigDirectorClientOptions(
          connection: ConnectionOptions(
            mode: ConnectionMode.offline,
            values: const {'new-checkout': true},
            baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
          ),
        ),
      );

      await client.initialize(ConfigDirectorContext(id: 'user-1'));
      client.getValue('new-checkout', false);
      await client.updateContext(ConfigDirectorContext(id: 'user-2'));
      client.pauseNetwork();
      await client.resumeNetwork();
      client.dispose();
      await Future<void>.delayed(const Duration(seconds: 1));
    }, createHttpClient: (_) => _RecordingHttpClient(httpClients.add));

    expect(httpClients, isEmpty);
    expect(requestedUrls, isEmpty);
  });
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(void Function(_RecordingHttpClient) onCreated) {
    onCreated(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('An offline client must not use HTTP: $invocation');
}
