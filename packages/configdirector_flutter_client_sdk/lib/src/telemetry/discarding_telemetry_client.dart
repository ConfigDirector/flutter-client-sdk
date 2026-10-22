import '../types.dart';
import 'telemetry_client.dart';
import 'telemetry_events.dart';

final class DiscardingTelemetryClient implements TelemetryClient {
  const DiscardingTelemetryClient();

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
