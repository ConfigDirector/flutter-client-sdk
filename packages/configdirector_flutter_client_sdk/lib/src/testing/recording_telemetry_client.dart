import '../logger.dart';
import '../telemetry/telemetry_client.dart';
import '../telemetry/telemetry_events.dart';
import '../telemetry/tracked_events.dart';
import '../types.dart';
import 'tracked_event.dart';

final class RecordingTelemetryClient implements TelemetryClient {
  RecordingTelemetryClient(this._logger);

  final ConfigDirectorLogger _logger;

  final List<TrackedEvent> trackedEvents = [];

  @override
  void trackedEvent(
    TrackedEventAdmission admission,
    ConfigDirectorContext? context,
  ) {
    for (final warning in admission.warnings) {
      _logger.warn(warning.message);
    }

    switch (admission) {
      case TrackedEventDropped():
        return;
      case TrackedEventAdmitted(:final entry):
        trackedEvents.add(
          TrackedEvent(
            name: entry.name,
            context: context,
            value: entry.value,
            details: entry.details,
          ),
        );
    }
  }

  @override
  void evaluatedConfig(EvaluatedConfigEvent event) {}

  @override
  void recordInvalidContextSubmission(String contextKindSample) {}

  @override
  Future<void> updateContext(ConfigDirectorContext? context) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
