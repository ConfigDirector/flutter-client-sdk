import '../logger.dart';
import 'event_reporter.dart';
import 'isolate_event_reporter.dart';

/// Returns a reporter that prepares and sends reports from a background
/// isolate.
EventReporter createEventReporter({
  required String sdkKey,
  required Uri baseUrl,
  required ConfigDirectorLogger logger,
}) => IsolateEventReporter(sdkKey: sdkKey, baseUrl: baseUrl, logger: logger);
