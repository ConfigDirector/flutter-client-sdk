import 'dart:async';

import 'package:configdirector_flutter_client_sdk/src/telemetry/event_reporter.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_event_collector.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_events.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const Duration _initialFlushDelay = Duration(seconds: 5);
const Duration _flushInterval = Duration(seconds: 30);

EvaluatedConfigEvent evaluation([String key = 'dark-mode']) =>
    EvaluatedConfigEvent.fromEvaluation(
      key: key,
      type: ConfigType.boolean,
      defaultValue: false,
      evaluatedValue: true,
      requestedType: 'bool',
      usedDefault: false,
      evaluationReason: EvaluationReason.foundMatch,
    );

void main() {
  late FakeEventReporter reporter;
  late RecordingLogger logger;

  setUp(() {
    reporter = FakeEventReporter();
    logger = RecordingLogger();
  });

  TelemetryEventCollector createCollector({int eventQueueLimit = 1000}) =>
      TelemetryEventCollector(
        reporter: reporter,
        logger: logger,
        flushInterval: _flushInterval,
        initialFlushDelay: _initialFlushDelay,
        eventQueueLimit: eventQueueLimit,
      );

  List<EvaluatedConfigEvent> reportedEvents(int index) =>
      reporter.requests[index].snapshot.events;

  test('reports what it collected once the first flush comes due', () {
    fakeAsync((async) {
      createCollector().evaluatedConfig(evaluation());

      async.elapse(_initialFlushDelay - const Duration(seconds: 1));
      expect(reporter.requests, isEmpty);

      async.elapse(const Duration(seconds: 1));
      expect(reportedEvents(0), [evaluation()]);
    });
  });

  test('overlapping flushes leave a single flush scheduled', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());

      unawaited(collector.flush());
      unawaited(collector.flush());
      async.flushMicrotasks();

      expect(async.pendingTimers, hasLength(1));
    });
  });

  test('keeps reporting on the flush interval', () {
    fakeAsync((async) {
      final collector = createCollector();

      collector.evaluatedConfig(evaluation());
      async.elapse(_initialFlushDelay);
      collector.evaluatedConfig(evaluation('greeting'));
      async.elapse(_flushInterval);

      expect(reporter.requests, hasLength(2));
      expect(reportedEvents(1), [evaluation('greeting')]);
    });
  });

  test('reports nothing while nothing is being evaluated', () {
    fakeAsync((async) {
      createCollector();

      async.elapse(_initialFlushDelay + _flushInterval * 3);

      expect(reporter.requests, isEmpty);
    });
  });

  test('empties the queue as it reports', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());

      async.elapse(_initialFlushDelay);
      collector.evaluatedConfig(evaluation('greeting'));
      async.elapse(_flushInterval);

      expect(reportedEvents(0), hasLength(1));
      expect(reportedEvents(1), [evaluation('greeting')]);
    });
  });

  test('drops the oldest events once the queue is full', () {
    fakeAsync((async) {
      final collector = createCollector(eventQueueLimit: 2);

      for (final key in ['a', 'b', 'c', 'd']) {
        collector.evaluatedConfig(evaluation(key));
      }
      async.elapse(_initialFlushDelay);

      expect(reportedEvents(0), [evaluation('c'), evaluation('d')]);
      expect(reporter.requests.single.snapshot.droppedCount, 2);
    });
  });

  test('attributes the events it collects to the current context', () {
    fakeAsync((async) {
      final collector = createCollector();
      const context = ConfigDirectorContext(id: 'user-123');

      unawaited(collector.updateContext(context));
      collector.evaluatedConfig(evaluation());
      async.elapse(_initialFlushDelay);

      expect(reporter.requests.single.context, context);
    });
  });

  test('reports what came before a context update against the old context', () {
    fakeAsync((async) {
      final collector = createCollector();

      unawaited(collector.updateContext(const ConfigDirectorContext(id: 'a')));
      collector.evaluatedConfig(evaluation());
      async.flushMicrotasks();

      unawaited(collector.updateContext(const ConfigDirectorContext(id: 'b')));
      collector.evaluatedConfig(evaluation('greeting'));
      async.elapse(_initialFlushDelay);

      expect(reporter.requests.map((r) => r.context?.id), ['a', 'b']);
      expect(reportedEvents(0), [evaluation()]);
      expect(reportedEvents(1), [evaluation('greeting')]);
    });
  });

  test('flush() reports right away and puts the interval back', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());

      unawaited(collector.flush());
      async.flushMicrotasks();
      expect(reporter.requests, hasLength(1));

      collector.evaluatedConfig(evaluation());
      async.elapse(_flushInterval - const Duration(seconds: 1));
      expect(reporter.requests, hasLength(1));

      async.elapse(const Duration(seconds: 1));
      expect(reporter.requests, hasLength(2));
    });
  });

  test('does not let two flushes take from the queue at the same time', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());
      reporter.gate = Completer<void>();

      unawaited(collector.flush());
      async.flushMicrotasks();
      collector.evaluatedConfig(evaluation('greeting'));
      unawaited(collector.flush());
      async.flushMicrotasks();

      expect(reporter.requests, hasLength(1));

      reporter.gate!.complete();
      async.flushMicrotasks();

      expect(reporter.requests, hasLength(2));
      expect(reportedEvents(1), [evaluation('greeting')]);
    });
  });

  test('stops collecting after a fatal error', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());
      reporter.response = const ReporterResponse.failed(fatalError: true);

      async.elapse(_initialFlushDelay);
      collector.evaluatedConfig(evaluation());
      async.elapse(_flushInterval * 3);

      expect(reporter.requests, hasLength(1));
      expect(reporter.closeCount, 1);
      expect(
        logger.messages,
        contains(contains('No longer collecting events')),
      );
    });
  });

  test('keeps collecting after a failure that is not fatal', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());
      reporter.response = const ReporterResponse.failed();

      async.elapse(_initialFlushDelay);
      collector.evaluatedConfig(evaluation());
      async.elapse(_flushInterval);

      expect(reporter.requests, hasLength(2));
    });
  });

  test('keeps collecting when the reporter throws', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());
      reporter.error = StateError('boom');

      async.elapse(_initialFlushDelay);
      collector.evaluatedConfig(evaluation());
      reporter.error = null;
      async.elapse(_flushInterval);

      expect(reporter.requests, hasLength(2));
      expect(logger.messages, contains(contains('Error reporting telemetry')));
    });
  });

  test('reports what is left when it closes', () {
    fakeAsync((async) {
      final collector = createCollector()..evaluatedConfig(evaluation());

      unawaited(collector.close());
      async.flushMicrotasks();

      expect(reportedEvents(0), [evaluation()]);
      expect(reporter.closeCount, 1);
    });
  });

  test('collects and reports nothing once closed', () {
    fakeAsync((async) {
      final collector = createCollector();

      unawaited(collector.close());
      async.flushMicrotasks();
      collector.evaluatedConfig(evaluation());
      unawaited(collector.flush());
      async.elapse(_initialFlushDelay + _flushInterval);

      expect(reporter.requests, isEmpty);
      expect(reporter.closeCount, 1);
    });
  });

  test('close() is safe to call twice', () {
    fakeAsync((async) {
      final collector = createCollector();

      unawaited(collector.close());
      unawaited(collector.close());
      async.flushMicrotasks();

      expect(reporter.closeCount, 1);
    });
  });
}
