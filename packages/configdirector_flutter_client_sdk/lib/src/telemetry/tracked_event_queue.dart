import 'tracked_events.dart';

final class TrackedEventQueue {
  final Set<TrackedEventWarning> _warningsRaisedThisBatch = {};
  List<TrackedEventEntry> _entries = [];

  List<TrackedEventWarning> add(TrackedEventAdmission admission) => [
    for (final warning in _warningsOfKeeping(admission))
      if (_isFirstThisBatch(warning)) warning,
  ];

  List<TrackedEventEntry> takeBatch() {
    final batch = _entries;
    clear();
    return batch;
  }

  void clear() {
    _entries = [];
    _warningsRaisedThisBatch.clear();
  }

  List<TrackedEventWarning> _warningsOfKeeping(
    TrackedEventAdmission admission,
  ) {
    switch (admission) {
      case TrackedEventDropped(:final warnings):
        return warnings;
      case TrackedEventAdmitted(:final entry, :final warnings):
        if (_entries.length >= trackedEventsPerBatch) {
          return const [TrackedEventWarning.batchAlreadyFull];
        }
        _entries.add(entry);
        return warnings;
    }
  }

  bool _isFirstThisBatch(TrackedEventWarning warning) =>
      _warningsRaisedThisBatch.add(warning);
}
