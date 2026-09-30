// Intercepts dart:io's HttpClient, so it only runs where dart:io works.
@TestOn('vm')
library;

import 'dart:io';

import 'package:configdirector_flutter_client_sdk/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S23 no HTTP client is created or used', () async {
    final httpClients = <_RecordingHttpClient>[];

    await HttpOverrides.runZoned(() async {
      final testClient = createTestClient(values: {'flag': true, 'count': 2});
      final client = testClient.client;
      addTearDown(client.dispose);

      await client.initialize();
      expect(client.getValue('flag', false), isTrue);
      expect(client.getValue('count', 0), 2);
      testClient.setValue('flag', false);
      await pumpEventQueue();
      expect(client.getValue('flag', true), isFalse);
      client.dispose();
      await pumpEventQueue();
    }, createHttpClient: (_) => _RecordingHttpClient(httpClients.add));

    expect(httpClients, isEmpty);
  });
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(void Function(_RecordingHttpClient) onCreated) {
    onCreated(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('The test client must not use HTTP: $invocation');
}
