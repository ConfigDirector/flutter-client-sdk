import 'dart:async';
import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/src/telemetry/event_queue.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/event_reporter.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_events.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/value_id.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

EvaluatedConfigEvent evaluation({
  String key = 'dark-mode',
  ConfigType type = ConfigType.boolean,
  Object defaultValue = false,
  Object evaluatedValue = true,
  String? evaluatedValueId = 'value-id',
  String requestedType = 'bool',
  bool usedDefault = false,
  EvaluationReason reason = EvaluationReason.foundMatch,
  String? contextId,
}) => EvaluatedConfigEvent.fromEvaluation(
  contextId: contextId,
  key: key,
  type: type,
  defaultValue: defaultValue,
  evaluatedValue: evaluatedValue,
  evaluatedValueId: evaluatedValueId,
  requestedType: requestedType,
  usedDefault: usedDefault,
  evaluationReason: reason,
);

EventReportRequest requestOf(
  List<EvaluatedConfigEvent> events, {
  ConfigDirectorContext? context,
  int droppedCount = 0,
}) => EventReportRequest(
  context: context,
  snapshot: EventQueueSnapshot(
    startTime: DateTime.utc(2026),
    endTime: DateTime.utc(2026, 1, 1, 0, 0, 30),
    events: events,
    droppedCount: droppedCount,
  ),
);

void main() {
  late RecordingLogger logger;
  late List<http.Request> requests;

  setUp(() {
    logger = RecordingLogger();
    requests = [];
  });

  HttpEventReporter reporterWith(
    FutureOr<http.Response> Function(http.Request request) handler, {
    Duration timeout = const Duration(seconds: 5),
  }) => HttpEventReporter(
    sdkKey: 'a-client-sdk-key',
    baseUrl: Uri.parse('https://sdk.example.com'),
    metaContext: const TelemetryMetaContext(
      sdkName: 'reporter-tests',
      sdkVersion: '1.0.1',
    ),
    logger: logger,
    timeout: timeout,
    httpClient: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
  );

  Map<String, Object?> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, Object?>;

  test('posts the report to the telemetry endpoint', () async {
    final reporter = reporterWith((_) => http.Response('', 202));

    final response = await reporter.report(requestOf([evaluation()]));

    expect(response.success, isTrue);
    expect(response.fatalError, isFalse);
    expect(
      requests.single.url.toString(),
      'https://sdk.example.com/client/telemetry/v1',
    );
    expect(
      requests.single.headers['Content-Type'],
      startsWith('application/json'),
    );
  });

  test(
    'reports every evaluation with the context it was evaluated against',
    () async {
      final reporter = reporterWith((_) => http.Response('', 202));

      await reporter.report(
        requestOf(
          [
            evaluation(),
            evaluation(),
            evaluation(
              key: 'greeting',
              type: ConfigType.string,
              defaultValue: 'hi',
              evaluatedValue: 'hello',
              requestedType: 'String',
            ),
          ],
          context: const ConfigDirectorContext(id: 'user-123', name: 'Ada'),
          droppedCount: 3,
        ),
      );

      expect(bodyOf(requests.single), {
        'clientSdkKey': 'a-client-sdk-key',
        'context': {'id': 'user-123', 'name': 'Ada'},
        'metaContext': {'sdkName': 'reporter-tests', 'sdkVersion': '1.0.1'},
        'discreteEvents': <String, Object?>{},
        'aggregatedEvents': {
          'evaluatedConfig': [
            {
              'startTime': '2026-01-01T00:00:00.000Z',
              'endTime': '2026-01-01T00:00:30.000Z',
              'count': 2,
              'event': {
                'key': 'dark-mode',
                'type': 'boolean',
                'defaultValue': {'value': 'false'},
                'requestedType': 'bool',
                'evaluatedValue': {'value': 'true'},
                'evaluatedValueId': 'value-id',
                'usedDefault': false,
                'evaluationReason': 'found-match',
              },
            },
            {
              'startTime': '2026-01-01T00:00:00.000Z',
              'endTime': '2026-01-01T00:00:30.000Z',
              'count': 1,
              'event': {
                'key': 'greeting',
                'type': 'string',
                'defaultValue': {'value': 'hi'},
                'requestedType': 'String',
                'evaluatedValue': {'value': 'hello'},
                'evaluatedValueId': 'value-id',
                'usedDefault': false,
                'evaluationReason': 'found-match',
              },
            },
          ],
        },
        'droppedEvents': {'evaluatedConfig': 3},
      });
    },
  );

  test('reports a value too large to send by its id', () async {
    final reporter = reporterWith((_) => http.Response('', 202));
    final value = 'a' * 501;

    await reporter.report(
      requestOf([
        evaluation(
          type: ConfigType.string,
          defaultValue: value,
          evaluatedValue: value,
          evaluatedValueId: null,
          requestedType: 'String',
        ),
      ]),
    );

    final event =
        ((bodyOf(requests.single)['aggregatedEvents']
                        as Map<String, Object?>)['evaluatedConfig']
                    as List)
                .single
            as Map;
    expect(
      event['event'],
      containsPair('defaultValue', {'valueId': generateValueId(value)}),
    );
    expect(
      event['event'],
      containsPair('evaluatedValue', {'valueId': generateValueId(value)}),
    );
  });

  test('omits the context when there is none', () async {
    final reporter = reporterWith((_) => http.Response('', 202));

    await reporter.report(requestOf([evaluation()]));

    expect(bodyOf(requests.single), isNot(contains('context')));
  });

  test('sends nothing when there is nothing to report', () async {
    final reporter = reporterWith((_) => http.Response('', 202));

    final response = await reporter.report(requestOf([]));

    expect(response.success, isTrue);
    expect(requests, isEmpty);
  });

  test('still reports events that were dropped', () async {
    final reporter = reporterWith((_) => http.Response('', 202));

    await reporter.report(requestOf([], droppedCount: 7));

    expect(bodyOf(requests.single)['droppedEvents'], {'evaluatedConfig': 7});
  });

  test('treats a client error as fatal and stops sending', () async {
    final reporter = reporterWith((_) => http.Response('nope', 401));

    final response = await reporter.report(requestOf([evaluation()]));
    final afterFatal = await reporter.report(requestOf([evaluation()]));

    expect(response.success, isFalse);
    expect(response.fatalError, isTrue);
    expect(afterFatal.fatalError, isTrue);
    expect(requests, hasLength(1));
    expect(logger.messages, contains(contains('fatal status response (401)')));
  });

  test('keeps sending after a server error', () async {
    final reporter = reporterWith((_) => http.Response('', 503));

    final response = await reporter.report(requestOf([evaluation()]));
    await reporter.report(requestOf([evaluation()]));

    expect(response.success, isFalse);
    expect(response.fatalError, isFalse);
    expect(requests, hasLength(2));
  });

  test('does not fail when the request fails', () async {
    final reporter = reporterWith((_) => throw const SocketExceptionStub());

    final response = await reporter.report(requestOf([evaluation()]));

    expect(response.success, isFalse);
    expect(response.fatalError, isFalse);
    expect(logger.messages, contains(contains('Error attempting to send')));
  });

  test('gives up on a request that takes too long', () async {
    final reporter = reporterWith(
      (_) => Future.delayed(
        const Duration(milliseconds: 200),
        () => http.Response('', 202),
      ),
      timeout: const Duration(milliseconds: 20),
    );

    final response = await reporter.report(requestOf([evaluation()]));

    expect(response.success, isFalse);
    expect(response.fatalError, isFalse);
    expect(logger.messages, contains(contains('Timed out after 20ms')));
  });
}

/// Stands in for the connection errors the HTTP client throws, which differ by
/// platform.
final class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'Connection refused';
}
