import '../logger.dart';
import 'event_reporter.dart';

/// Returns a reporter that prepares and sends reports on the current thread,
/// which on the web is the only one available to a Flutter package.
EventReporter createEventReporter({
  required String sdkKey,
  required Uri baseUrl,
  required ConfigDirectorLogger logger,
}) => HttpEventReporter(sdkKey: sdkKey, baseUrl: baseUrl, logger: logger);
