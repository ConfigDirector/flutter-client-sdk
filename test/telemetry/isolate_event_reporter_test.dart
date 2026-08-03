@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:configdirector_flutter_client_sdk/src/telemetry/event_queue.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/event_reporter.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/isolate_event_reporter.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_events.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

EventReportRequest requestOf({
  List<String> keys = const ['dark-mode'],
  ConfigDirectorContext? context,
}) => EventReportRequest(
  context: context,
  snapshot: EventQueueSnapshot(
    startTime: DateTime.utc(2026),
    endTime: DateTime.utc(2026, 1, 1, 0, 0, 30),
    events: [
      for (final key in keys)
        EvaluatedConfigEvent.fromEvaluation(
          key: key,
          type: ConfigType.boolean,
          defaultValue: false,
          evaluatedValue: true,
          requestedType: 'bool',
          usedDefault: false,
          evaluationReason: EvaluationReason.foundMatch,
        ),
    ],
    droppedCount: 0,
  ),
);

void main() {
  late HttpServer server;
  late RecordingLogger logger;
  late List<Map<String, Object?>> received;
  late int status;

  setUp(() async {
    logger = RecordingLogger();
    received = [];
    status = 202;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        received.add(
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>,
        );
        request.response.statusCode = status;
        await request.response.close();
      }),
    );
  });

  tearDown(() => server.close(force: true));

  IsolateEventReporter createReporter() => IsolateEventReporter(
    sdkKey: 'a-client-sdk-key',
    baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
    logger: logger,
  );

  test('prepares and sends the report from a background isolate', () async {
    final reporter = createReporter();
    addTearDown(reporter.close);

    final response = await reporter.report(
      requestOf(context: const ConfigDirectorContext(id: 'user-123')),
    );

    expect(response.success, isTrue);
    expect(response.fatalError, isFalse);
    expect(received.single['clientSdkKey'], 'a-client-sdk-key');
    expect(received.single['context'], {'id': 'user-123'});
  });

  test('keeps the isolate for the reports that follow', () async {
    final reporter = createReporter();
    addTearDown(reporter.close);

    await reporter.report(requestOf());
    await reporter.report(requestOf(keys: ['greeting']));

    expect(received, hasLength(2));
  });

  test(
    'reports what the isolate logs through the application logger',
    () async {
      status = 401;
      final reporter = createReporter();
      addTearDown(reporter.close);

      final response = await reporter.report(requestOf());

      expect(response.fatalError, isTrue);
      expect(
        logger.messages,
        contains(contains('fatal status response (401)')),
      );
    },
  );

  test('does not start the isolate when there is nothing to report', () async {
    final reporter = createReporter();
    addTearDown(reporter.close);

    final response = await reporter.report(requestOf(keys: const []));

    expect(response.success, isTrue);
    expect(received, isEmpty);
  });

  test('stops reporting once closed', () async {
    final reporter = createReporter();

    await reporter.report(requestOf());
    await reporter.close();
    final response = await reporter.report(requestOf());

    expect(response.success, isFalse);
    expect(received, hasLength(1));
  });

  test('shuts the isolate down even while it is still starting', () async {
    final reporter = createReporter();

    // No `await`: the isolate is still being spawned when the close lands.
    final report = reporter.report(requestOf());
    await reporter.close();

    expect((await report).success, isFalse);
    expect(received, isEmpty);
  });

  test(
    'close() is safe to call twice, and before anything was reported',
    () async {
      final reporter = createReporter();

      await reporter.close();

      expect(reporter.close, returnsNormally);
    },
  );
}
