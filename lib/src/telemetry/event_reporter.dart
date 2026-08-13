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

@immutable
final class TelemetryMetaContext {
  const TelemetryMetaContext({required this.sdkName, required this.sdkVersion});

  final String sdkName;
  final String sdkVersion;

  Map<String, Object?> toJson() => {
    'sdkName': sdkName,
    'sdkVersion': sdkVersion,
  };
}

@immutable
final class EventReportRequest {
  const EventReportRequest({required this.snapshot, this.context});

  final EventQueueSnapshot<EvaluatedConfigEvent> snapshot;

  final ConfigDirectorContext? context;
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
    required TelemetryMetaContext metaContext,
    required ConfigDirectorLogger logger,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
  }) : _sdkKey = sdkKey,
       _url = baseUrl.resolve('client/telemetry/v1'),
       _metaContext = metaContext,
       _logger = logger,
       _timeout = timeout,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final String _sdkKey;
  final Uri _url;
  final TelemetryMetaContext _metaContext;
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

    final events = [
      for (final event in request.snapshot.events) event.compacted(),
    ];
    final aggregated = aggregateEvents(
      EventQueueSnapshot(
        startTime: request.snapshot.startTime,
        endTime: request.snapshot.endTime,
        events: events,
        droppedCount: request.snapshot.droppedCount,
      ),
    );

    if (aggregated.isEmpty && request.snapshot.droppedCount == 0) {
      return const ReporterResponse.succeeded();
    }

    final response = await _send(
      jsonEncode({
        'clientSdkKey': _sdkKey,
        'metaContext': _metaContext.toJson(),
        if (request.context != null) 'context': request.context!.toJson(),
        'discreteEvents': const <String, Object?>{},
        'aggregatedEvents': {
          'evaluatedConfig': [
            for (final event in aggregated) event.toJson((e) => e.toJson()),
          ],
        },
        'droppedEvents': {'evaluatedConfig': request.snapshot.droppedCount},
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
    if (isStatusFatal(status)) {
      _logger.warn(
        '[EventReporter] Received a fatal status response ($status) from the '
        'telemetry endpoint. No more telemetry data will be sent.',
      );
      return const ReporterResponse.failed(fatalError: true);
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
}
