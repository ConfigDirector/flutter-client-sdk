import 'event_aggregator.dart';
import 'telemetry_events.dart';

const int _contextKindSampleLimit = 20;

final class InvalidContextSubmissions {
  final Map<String, int> _countsByContextKindSample = {};
  int _countBeyondContextKindSampleLimit = 0;
  final Map<ContextSizeLimitReason, int> _countsBySizeLimitReason = {};
  DateTime? _startTime;

  void recordInvalidContextKind(String contextKindSample) {
    _startTime ??= DateTime.now();

    final isAlreadySampled = _countsByContextKindSample.containsKey(
      contextKindSample,
    );
    final hasRoomForAnotherSample =
        _countsByContextKindSample.length < _contextKindSampleLimit;
    if (isAlreadySampled || hasRoomForAnotherSample) {
      _countsByContextKindSample.update(
        contextKindSample,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    } else {
      _countBeyondContextKindSampleLimit += 1;
    }
  }

  void recordOverSizeLimit(ContextSizeLimitReason reason) {
    _startTime ??= DateTime.now();

    _countsBySizeLimitReason.update(
      reason,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  List<AggregatedEvent<InvalidContextSubmission>> takeAggregated() {
    final endTime = DateTime.now();
    final startTime = _startTime ?? endTime;
    final aggregated = [
      for (final MapEntry(key: contextKindSample, value: count)
          in _countsByContextKindSample.entries)
        AggregatedEvent(
          startTime: startTime,
          endTime: endTime,
          count: count,
          event: InvalidContextSubmission.sampled(contextKindSample),
        ),
      if (_countBeyondContextKindSampleLimit > 0)
        AggregatedEvent(
          startTime: startTime,
          endTime: endTime,
          count: _countBeyondContextKindSampleLimit,
          event: const InvalidContextSubmission.beyondContextKindSampleLimit(),
        ),
      for (final MapEntry(key: reason, value: count)
          in _countsBySizeLimitReason.entries)
        AggregatedEvent(
          startTime: startTime,
          endTime: endTime,
          count: count,
          event: InvalidContextSubmission.overSizeLimit(reason),
        ),
    ];

    clear();
    return aggregated;
  }

  void clear() {
    _countsByContextKindSample.clear();
    _countBeyondContextKindSampleLimit = 0;
    _countsBySizeLimitReason.clear();
    _startTime = null;
  }
}
