import 'dart:async';

import '../logger.dart';
import '../types.dart';
import 'event_queue.dart';
import 'event_reporter.dart';
import 'telemetry_client.dart';
import 'telemetry_events.dart';

/// The default [TelemetryClient]: it queues evaluations as they happen and
/// hands them to an [EventReporter] on an interval.
///
/// Collecting an event only appends it to a bounded in-memory queue, which is
/// what keeps evaluating a config cheap. Everything expensive — hashing large
/// values, aggregating, encoding, and the request itself — happens in the
/// reporter, which off the web runs in its own isolate.
final class TelemetryEventCollector implements TelemetryClient {
  TelemetryEventCollector({
    required EventReporter reporter,
    required ConfigDirectorLogger logger,
    this.flushInterval = const Duration(seconds: 30),
    Duration initialFlushDelay = const Duration(seconds: 5),
    int eventQueueLimit = 1000,
  }) : _reporter = reporter,
       _logger = logger,
       _queue = EventQueue(limit: eventQueueLimit) {
    // The first flush comes early so that an app that is opened briefly still
    // reports what it evaluated.
    _flushTimer = Timer(initialFlushDelay, _onFlushTimer);
  }

  /// How long the collector waits between flushes.
  final Duration flushInterval;

  final EventReporter _reporter;
  final ConfigDirectorLogger _logger;
  final EventQueue<EvaluatedConfigEvent> _queue;

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
    _queue.push(event);
  }

  @override
  Future<void> updateContext(ConfigDirectorContext? context) async {
    if (_closed) {
      return;
    }

    // Events collected until now belong to the context they were evaluated
    // against, so they are taken out of the queue before the new context takes
    // over. Both happen before this returns, leaving no window in which an
    // evaluation could be attributed to the wrong context.
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
    _queue.clear();
  }

  void _onFlushTimer() => unawaited(_flushAndScheduleNext());

  Future<void> _flushAndScheduleNext() async {
    await _flush();

    if (!_collecting || _closed) {
      return;
    }
    _flushTimer = Timer(flushInterval, _onFlushTimer);
  }

  /// Empties the queue into a report and sends it behind any report already in
  /// flight.
  ///
  /// The interval, a context update, the app being backgrounded, and [close]
  /// can all ask for a flush at any time, so the queue is emptied here and now,
  /// synchronously, and only sending waits its turn.
  Future<void> _flush() {
    if (_queue.isEmpty) {
      // Nothing new to send, but a report may still be on its way out, and
      // callers such as [close] have to wait for it.
      return _flushChain;
    }

    final request = EventReportRequest(
      snapshot: _queue.takeSnapshot(),
      context: _context,
    );
    final flush = _flushChain.then((_) => _send(request));
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

  void _stopCollecting() {
    _collecting = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _queue.clear();
    unawaited(_reporter.close());
    _logger.warn(
      '[TelemetryEventCollector] Received a fatal error while reporting '
      'telemetry. No longer collecting events.',
    );
  }
}
