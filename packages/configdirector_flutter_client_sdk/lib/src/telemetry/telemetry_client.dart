import '../types.dart';
import 'telemetry_events.dart';

/// Collects what the SDK reports back to ConfigDirector.
///
/// Everything here is called from the client's hot path, so implementations
/// must return without doing any appreciable work.
abstract interface class TelemetryClient {
  /// Records that a config was evaluated.
  void evaluatedConfig(EvaluatedConfigEvent event);

  /// Reports the events collected so far against the previous context, and
  /// attributes the ones collected from now on to [context].
  Future<void> updateContext(ConfigDirectorContext? context);

  /// Reports everything collected so far without waiting for the next flush.
  Future<void> flush();

  /// Reports whatever is left and releases every resource held.
  Future<void> close();
}
