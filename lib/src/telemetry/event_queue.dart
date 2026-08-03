import 'package:flutter/foundation.dart';

/// Everything an [EventQueue] had collected when a report was prepared.
@immutable
final class EventQueueSnapshot<T> {
  const EventQueueSnapshot({
    required this.startTime,
    required this.endTime,
    required this.events,
    required this.droppedCount,
  });

  /// When the first of the [events] was collected.
  final DateTime startTime;

  /// When the snapshot was taken.
  final DateTime endTime;

  final List<T> events;

  /// How many events were dropped because the queue was full.
  final int droppedCount;

  bool get isEmpty => events.isEmpty && droppedCount == 0;
}

/// Holds collected events until they are reported.
///
/// The queue is bounded: once it is full, the oldest events are dropped to make
/// room for new ones, and the number dropped is reported alongside the events
/// that were kept.
final class EventQueue<T> {
  EventQueue({this.limit = 1000});

  /// The most events the queue holds before it starts dropping the oldest.
  final int limit;

  final List<T> _events = [];
  DateTime? _startTime;
  int _droppedCount = 0;

  @visibleForTesting
  List<T> get events => List.unmodifiable(_events);

  bool get isEmpty => _events.isEmpty && _droppedCount == 0;

  void push(T event) {
    _startTime ??= DateTime.now();

    if (_events.length >= limit) {
      final dropCount = _events.length - limit + 1;
      _events.removeRange(0, dropCount);
      _droppedCount += dropCount;
    }
    _events.add(event);
  }

  /// Removes every event from the queue and returns it, leaving the queue ready
  /// to collect the next batch.
  EventQueueSnapshot<T> takeSnapshot() {
    final endTime = DateTime.now();
    final snapshot = EventQueueSnapshot<T>(
      startTime: _startTime ?? endTime,
      endTime: endTime,
      events: List.of(_events),
      droppedCount: _droppedCount,
    );

    clear();
    return snapshot;
  }

  void clear() {
    _events.clear();
    _startTime = null;
    _droppedCount = 0;
  }
}
