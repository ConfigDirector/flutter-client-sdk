import 'package:configdirector_flutter_client_sdk/src/telemetry/event_aggregator.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/event_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventQueue', () {
    test('rejects a limit that cannot hold an event', () {
      expect(() => EventQueue<String>(limit: 0), throwsArgumentError);
      expect(() => EventQueue<String>(limit: -1), throwsArgumentError);
    });

    test('starts out empty', () {
      final queue = EventQueue<String>();

      expect(queue.isEmpty, isTrue);
      expect(queue.takeSnapshot().isEmpty, isTrue);
    });

    test('holds the events pushed into it', () {
      final queue = EventQueue<String>()
        ..push('a')
        ..push('b');

      final snapshot = queue.takeSnapshot();

      expect(snapshot.events, ['a', 'b']);
      expect(snapshot.droppedCount, 0);
      expect(snapshot.isEmpty, isFalse);
    });

    test('drops the oldest events once it is full', () {
      final queue = EventQueue<int>(limit: 3);
      for (var i = 0; i < 5; i++) {
        queue.push(i);
      }

      final snapshot = queue.takeSnapshot();

      expect(snapshot.events, [2, 3, 4]);
      expect(snapshot.droppedCount, 2);
    });

    test('covers the window the events were collected over', () {
      final queue = EventQueue<String>()..push('a');

      final snapshot = queue.takeSnapshot();

      expect(snapshot.startTime.isAfter(snapshot.endTime), isFalse);
      expect(
        DateTime.now().difference(snapshot.startTime),
        lessThan(const Duration(minutes: 1)),
      );
    });

    test('empties itself when a snapshot is taken', () {
      final queue = EventQueue<int>(limit: 1)
        ..push(1)
        ..push(2);

      expect(queue.takeSnapshot().droppedCount, 1);

      final snapshot = queue.takeSnapshot();
      expect(snapshot.events, isEmpty);
      expect(snapshot.droppedCount, 0);
    });

    test('clear discards everything collected so far', () {
      final queue = EventQueue<int>(limit: 1)
        ..push(1)
        ..push(2)
        ..clear();

      expect(queue.isEmpty, isTrue);
      expect(queue.takeSnapshot().droppedCount, 0);
    });
  });

  group('aggregateEvents', () {
    EventQueueSnapshot<String> snapshotOf(List<String> events) =>
        EventQueueSnapshot(
          startTime: DateTime.utc(2026),
          endTime: DateTime.utc(2026, 1, 1, 0, 0, 30),
          events: events,
          droppedCount: 0,
        );

    test('counts identical events once', () {
      final aggregated = aggregateEvents(snapshotOf(['a', 'b', 'a', 'a']));

      expect(aggregated.map((e) => (e.event, e.count)), [('a', 3), ('b', 1)]);
    });

    test('covers the window of the snapshot it came from', () {
      final snapshot = snapshotOf(['a']);

      final aggregated = aggregateEvents(snapshot).single;

      expect(aggregated.startTime, snapshot.startTime);
      expect(aggregated.endTime, snapshot.endTime);
    });

    test('aggregates nothing into nothing', () {
      expect(aggregateEvents(snapshotOf([])), isEmpty);
    });

    test('serializes the window as UTC timestamps', () {
      final aggregated = aggregateEvents(snapshotOf(['a'])).single;

      expect(aggregated.toJson((event) => {'name': event}), {
        'startTime': '2026-01-01T00:00:00.000Z',
        'endTime': '2026-01-01T00:00:30.000Z',
        'count': 1,
        'event': {'name': 'a'},
      });
    });
  });
}
