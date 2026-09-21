import 'package:flutter/foundation.dart';

import 'event_queue.dart';

/// A group of identical events, reported once with the number of times it
/// occurred.
@immutable
final class AggregatedEvent<T> {
  const AggregatedEvent({
    required this.startTime,
    required this.endTime,
    required this.count,
    required this.event,
  });

  final DateTime startTime;
  final DateTime endTime;
  final int count;
  final T event;

  Map<String, Object?> toJson(Map<String, Object?> Function(T event) encode) =>
      {
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
        'count': count,
        'event': encode(event),
      };
}

/// Collapses the identical events in [snapshot] into one entry each, carrying
/// how many times the event occurred over the window the snapshot covers.
List<AggregatedEvent<T>> aggregateEvents<T>(EventQueueSnapshot<T> snapshot) {
  final counts = <T, int>{};
  for (final event in snapshot.events) {
    counts.update(event, (count) => count + 1, ifAbsent: () => 1);
  }

  return [
    for (final entry in counts.entries)
      AggregatedEvent(
        startTime: snapshot.startTime,
        endTime: snapshot.endTime,
        count: entry.value,
        event: entry.key,
      ),
  ];
}
