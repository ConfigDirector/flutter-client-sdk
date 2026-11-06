import 'dart:async';

import '../logger.dart';
import '../types.dart';
import 'event_queue.dart';
import 'event_reporter.dart';
import 'invalid_context_submissions.dart';
import 'telemetry_client.dart';
import 'telemetry_events.dart';
import 'tracked_event_queue.dart';
import 'tracked_events.dart';

/// The default [TelemetryClient]: it queues evaluations and tracked events as
/// they happen and hands them to an [EventReporter] on an interval.
///
/// Collecting an event only appends it to a bounded in-memory queue, which is
/// what keeps evaluating a config cheap. Everything expensive — hashing large
/// values, aggregating, encoding, and the request itself — happens in the
/// reporter, which off the web runs in its own isolate.
final class TelemetryEventCollector implements TelemetryClient {
  TelemetryEventCollector({
    required EventReporter reporter,
    required SdkMetaContext Function() currentMetaContext,
    required Future<String> instanceId,
    required ConfigDirectorLogger logger,
    this.flushInterval = const Duration(seconds: 30),
    Duration initialFlushDelay = const Duration(seconds: 5),
    int evaluationQueueLimit = 1000,
  }) : _reporter = reporter,
       _currentMetaContext = currentMetaContext,
       _instanceId = instanceId,
       _logger = logger,
       _evaluationEventQueue = EventQueue(limit: evaluationQueueLimit) {
    _flushTimer = Timer(initialFlushDelay, _onFlushTimer);
  }

  final Duration flushInterval;

  final EventReporter _reporter;
  final SdkMetaContext Function() _currentMetaContext;
  final Future<String> _instanceId;
  final ConfigDirectorLogger _logger;
  final EventQueue<EvaluatedConfigEvent> _evaluationEventQueue;
  final InvalidContextSubmissions _invalidContextSubmissions =
      InvalidContextSubmissions();
  final TrackedEventQueue _trackedEventQueue = TrackedEventQueue();

  ConfigDirectorContext? _context;
  Timer? _flushTimer;
  Future<void> _flushChain = Future.value();
  bool _collecting = true;
  bool _closed = false;

  @override
  void evaluatedConfig(EvaluatedConfigEvent event) {
    if (!_collecting) {
      return;
    }
    _evaluationEventQueue.push(event);
  }

  @override
  void recordInvalidContextSubmission(String contextKindSample) {
    if (!_collecting) {
      return;
    }
    _invalidContextSubmissions.record(contextKindSample);
  }

  @override
  void trackedEvent(
    TrackedEventAdmission admission,
    ConfigDirectorContext? context,
  ) {
    if (!_collecting) {
      return;
    }
    for (final warning in _trackedEventQueue.add(admission)) {
      _logger.warn(
        '${warning.message} Further tracked events like it are not logged '
        'until the next telemetry batch is sent.',
      );
    }
  }

  @override
  Future<void> updateContext(ConfigDirectorContext? context) async {
    if (_closed) {
      return;
    }

    _flushTimer?.cancel();
    final flush = _flush();
    _context = context;
    await flush;

    await _flushAndScheduleNext();
  }

  @override
  Future<void> flush() {
    if (_closed) {
      return Future.value();
    }

    _flushTimer?.cancel();
    return _flushAndScheduleNext();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _collecting = false;
    _flushTimer?.cancel();
    _flushTimer = null;

    await _flush();
    await _reporter.close();
    _discardCollectedEvents();
  }

  void _onFlushTimer() => unawaited(_flushAndScheduleNext());

  Future<void> _flushAndScheduleNext() async {
    await _flush();

    if (!_collecting || _closed) {
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(flushInterval, _onFlushTimer);
  }

  Future<void> _flush() {
    final evaluationSnapshot = _evaluationEventQueue.takeSnapshot();
    final invalidContextSubmissions = _invalidContextSubmissions
        .takeAggregated();
    final trackedEventEntries = _trackedEventQueue.takeBatch();
    if (nothingToReport(
      evaluationSnapshot,
      invalidContextSubmissions,
      trackedEventEntries,
    )) {
      return _flushChain;
    }

    final metaContext = _currentMetaContext();
    final context = _context;
    final flush = _flushChain.then(
      (_) async => _send(
        EventReportRequest(
          evaluationSnapshot: evaluationSnapshot,
          invalidContextSubmissions: invalidContextSubmissions,
          trackedEventEntries: trackedEventEntries,
          metaContext: metaContext,
          instanceId: await _instanceId,
          context: context,
        ),
      ),
    );
    _flushChain = flush.catchError((Object _) {});
    return flush;
  }

  Future<void> _send(EventReportRequest request) async {
    final ReporterResponse response;
    try {
      response = await _reporter.report(request);
    } on Object catch (error, stackTrace) {
      _logger.warn(
        '[TelemetryEventCollector] Error reporting telemetry data',
        error,
        stackTrace,
      );
      return;
    }

    if (response.fatalError) {
      _stopCollecting();
    }
  }

  void _discardCollectedEvents() {
    _evaluationEventQueue.clear();
    _invalidContextSubmissions.clear();
    _trackedEventQueue.clear();
  }

  void _stopCollecting() {
    _collecting = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _discardCollectedEvents();
    unawaited(_reporter.close());
    _logger.warn(
      '[TelemetryEventCollector] Received a fatal error while reporting '
      'telemetry. No longer collecting events.',
    );
  }
}
