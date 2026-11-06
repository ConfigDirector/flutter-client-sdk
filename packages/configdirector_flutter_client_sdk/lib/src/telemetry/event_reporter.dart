import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../logger.dart';
import '../transport/transport.dart' show isStatusFatal;
import '../types.dart';
import 'event_aggregator.dart';
import 'event_queue.dart';
import 'telemetry_events.dart';
import 'tracked_events.dart';

const int _reportTooLargeStatus = 413;

bool nothingToReport(
  EventQueueSnapshot<EvaluatedConfigEvent> evaluationSnapshot,
  List<AggregatedEvent<InvalidContextSubmission>> invalidContextSubmissions,
  List<TrackedEventEntry> trackedEventEntries,
) =>
    evaluationSnapshot.isEmpty &&
    invalidContextSubmissions.isEmpty &&
    trackedEventEntries.isEmpty;

@immutable
final class EventReportRequest {
  const EventReportRequest({
    required this.evaluationSnapshot,
    required this.invalidContextSubmissions,
    required this.trackedEventEntries,
    required this.metaContext,
    required this.instanceId,
    this.context,
  });

  final EventQueueSnapshot<EvaluatedConfigEvent> evaluationSnapshot;

  final List<AggregatedEvent<InvalidContextSubmission>>
  invalidContextSubmissions;

  final List<TrackedEventEntry> trackedEventEntries;

  final SdkMetaContext metaContext;

  final String instanceId;

  final ConfigDirectorContext? context;

  bool get isEmpty => nothingToReport(
    evaluationSnapshot,
    invalidContextSubmissions,
    trackedEventEntries,
  );
}

@immutable
final class ReporterResponse {
  const ReporterResponse({required this.success, required this.fatalError});

  const ReporterResponse.succeeded() : success = true, fatalError = false;

  const ReporterResponse.failed({this.fatalError = false}) : success = false;

  final bool success;

  final bool fatalError;
}

abstract interface class EventReporter {
  Future<ReporterResponse> report(EventReportRequest request);

  Future<void> close();
}

final class HttpEventReporter implements EventReporter {
  HttpEventReporter({
    required String sdkKey,
    required Uri baseUrl,
    required ConfigDirectorLogger logger,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
  }) : _sdkKey = sdkKey,
       _url = baseUrl.resolve('client/telemetry/v1'),
       _logger = logger,
       _timeout = timeout,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final String _sdkKey;
  final Uri _url;
  final ConfigDirectorLogger _logger;
  final Duration _timeout;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  bool _executeRequests = true;

  @override
  Future<ReporterResponse> report(EventReportRequest request) async {
    if (!_executeRequests) {
      return const ReporterResponse.failed(fatalError: true);
    }
    if (request.isEmpty) {
      return const ReporterResponse.succeeded();
    }

    final events = [
      for (final event in request.evaluationSnapshot.events) event.compacted(),
    ];
    final aggregated = aggregateEvents(
      EventQueueSnapshot(
        startTime: request.evaluationSnapshot.startTime,
        endTime: request.evaluationSnapshot.endTime,
        events: events,
        droppedCount: request.evaluationSnapshot.droppedCount,
      ),
    );

    final response = await _send(
      jsonEncode({
        'clientSdkKey': _sdkKey,
        'instanceId': request.instanceId,
        'metaContext': request.metaContext.toJson(),
        if (request.context != null) 'context': request.context!.toJson(),
        'discreteEvents': {
          'trackedEvents': [
            for (final entry in request.trackedEventEntries) entry.toJson(),
          ],
        },
        'aggregatedEvents': {
          'evaluatedConfig': [
            for (final event in aggregated) event.toJson((e) => e.toJson()),
          ],
          'invalidContext': [
            for (final entry in request.invalidContextSubmissions)
              entry.toJson((submission) => submission.toJson()),
          ],
        },
        'droppedEvents': {
          'evaluatedConfig': request.evaluationSnapshot.droppedCount,
        },
      }),
    );

    if (response.fatalError) {
      _executeRequests = false;
    }
    return response;
  }

  Future<ReporterResponse> _send(String body) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(
            _url,
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
    } on TimeoutException {
      _logger.warn(
        '[EventReporter] Timed out after ${_timeout.inMilliseconds}ms sending '
        'telemetry data.',
      );
      return const ReporterResponse.failed();
    } on Object catch (error, stackTrace) {
      _logger.warn(
        '[EventReporter] Error attempting to send telemetry data',
        error,
        stackTrace,
      );
      return const ReporterResponse.failed();
    }

    final status = response.statusCode;
    if (_isReportStatusFatal(status)) {
      _logger.warn(
        '[EventReporter] Received a fatal status response ($status) from the '
        'telemetry endpoint. No more telemetry data will be sent.',
      );
      return const ReporterResponse.failed(fatalError: true);
    }
    if (status == _reportTooLargeStatus) {
      _logger.warn(
        '[EventReporter] The telemetry endpoint responded with status '
        '$status. The events in this report were discarded.',
      );
    }

    return status >= 200 && status < 300
        ? const ReporterResponse.succeeded()
        : const ReporterResponse.failed();
  }

  @override
  Future<void> close() async {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  static bool _isReportStatusFatal(int status) =>
      isStatusFatal(status) && status != _reportTooLargeStatus;
}
