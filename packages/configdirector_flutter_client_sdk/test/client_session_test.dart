import 'dart:async';
import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/src/client_session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const String _storedId = '11111111-1111-4111-8111-111111111111';
const Duration _sixHours = Duration(hours: 6);

void main() {
  late RecordingLogger logger;
  late FakeInstanceIdStorage storage;

  setUp(() {
    logger = RecordingLogger();
    storage = FakeInstanceIdStorage();
  });

  int now() => DateTime.now().millisecondsSinceEpoch;

  String record({
    String id = _storedId,
    required int createdAt,
    int version = 1,
  }) => jsonEncode({'v': version, 'id': id, 'createdAt': createdAt});

  Map<String, Object?> storedRecord() =>
      jsonDecode(storage.record!) as Map<String, Object?>;

  Future<ClientSession> settle() => settleClientSession(
    provisional: ClientSession.provisional(),
    storage: storage,
    logger: logger,
  );

  test(
    'reuses the stored instance ID while it is under six hours old',
    () async {
      final createdAt = now() - _sixHours.inMilliseconds + 60000;
      storage.record = record(createdAt: createdAt);

      final session = await settle();

      expect(session.instanceId, _storedId);
      expect(session.ephemeral, isFalse);
      expect(storage.writes, isEmpty);
      expect(storedRecord()['createdAt'], createdAt);
    },
  );

  test('generates an instance ID and stores it with its creation time when '
      'nothing is stored', () async {
    final before = now();

    final session = await settle();

    final after = now();
    expect(session.instanceId, matches(uuidV4Pattern));
    expect(session.ephemeral, isFalse);
    expect(storedRecord()['v'], 1);
    expect(storedRecord()['id'], session.instanceId);
    expect(
      storedRecord()['createdAt'],
      allOf(greaterThanOrEqualTo(before), lessThanOrEqualTo(after)),
    );
  });

  test(
    'generates and stores a new instance ID when the stored one is six hours '
    'old',
    () async {
      storage.record = record(createdAt: now() - _sixHours.inMilliseconds);

      final session = await settle();

      expect(session.instanceId, isNot(_storedId));
      expect(session.ephemeral, isFalse);
      expect(storedRecord()['id'], session.instanceId);
    },
  );

  test('generates a new instance ID when the stored creation time is in the '
      'future', () async {
    storage.record = record(createdAt: now() + 60000);

    final session = await settle();

    expect(session.instanceId, isNot(_storedId));
    expect(storedRecord()['id'], session.instanceId);
  });

  test('generates a new instance ID when the stored creation time is not '
      'positive', () async {
    storage.record = record(createdAt: 0);

    final session = await settle();

    expect(session.instanceId, isNot(_storedId));
    expect(storedRecord()['id'], session.instanceId);
  });

  test(
    'generates a new instance ID when the stored record has another version',
    () async {
      storage.record = record(createdAt: now(), version: 2);

      final session = await settle();

      expect(session.instanceId, isNot(_storedId));
      expect(storedRecord()['v'], 1);
      expect(storedRecord()['id'], session.instanceId);
    },
  );

  test(
    'generates a new instance ID when the stored one is not a UUID',
    () async {
      storage.record = record(id: 'instance-1', createdAt: now());

      final session = await settle();

      expect(session.instanceId, isNot('instance-1'));
      expect(storedRecord()['id'], session.instanceId);
    },
  );

  test('generates a new instance ID when the stored creation time is not a '
      'number', () async {
    storage.record = jsonEncode({
      'v': 1,
      'id': _storedId,
      'createdAt': '${now()}',
    });

    final session = await settle();

    expect(session.instanceId, isNot(_storedId));
    expect(storedRecord()['id'], session.instanceId);
  });

  test('generates a new instance ID when the stored record cannot be read as '
      'JSON', () async {
    storage.record = '{oops';

    final session = await settle();

    expect(session.ephemeral, isFalse);
    expect(storedRecord()['id'], session.instanceId);
  });

  test(
    'generates a new instance ID when the stored record is not a JSON object',
    () async {
      storage.record = '["$_storedId"]';

      final session = await settle();

      expect(session.ephemeral, isFalse);
      expect(storedRecord()['id'], session.instanceId);
    },
  );

  test('uses an ephemeral instance ID without writing when the storage cannot '
      'be read', () async {
    storage.record = record(createdAt: now());
    storage.readFailure = StateError('preferences unavailable');

    final session = await settle();

    expect(session.instanceId, matches(uuidV4Pattern));
    expect(session.ephemeral, isTrue);
    expect(storage.writes, isEmpty);
    expect(logger.warnings, hasLength(1));
  });

  test('uses an ephemeral instance ID when reading the storage throws before '
      'returning a future', () async {
    final session = await settleClientSession(
      provisional: ClientSession.provisional(),
      storage: _ThrowingInstanceIdStorage(),
      logger: logger,
    );

    expect(session.ephemeral, isTrue);
    expect(logger.warnings, hasLength(1));
  });

  test('uses an ephemeral instance ID when the storage reports the write did '
      'not happen', () async {
    storage.writeStores = false;

    final session = await settle();

    expect(session.instanceId, matches(uuidV4Pattern));
    expect(session.ephemeral, isTrue);
    expect(logger.warnings, hasLength(1));
  });

  test(
    'uses an ephemeral instance ID when writing to the storage throws',
    () async {
      storage.writeFailure = StateError('disk full');

      final session = await settle();

      expect(session.instanceId, matches(uuidV4Pattern));
      expect(session.ephemeral, isTrue);
      expect(storage.record, isNull);
      expect(logger.warnings, hasLength(1));
    },
  );

  group('deadline', () {
    test('falls back to an ephemeral instance ID one second after the read '
        'started, without writing', () {
      fakeAsync((async) {
        storage.heldRead = Completer<void>();
        ClientSession? settled;
        settle().then((session) => settled = session);

        async.elapse(const Duration(milliseconds: 999));

        expect(settled, isNull);

        async.elapse(const Duration(milliseconds: 1));

        expect(settled?.instanceId, matches(uuidV4Pattern));
        expect(settled?.ephemeral, isTrue);
        expect(storage.writes, isEmpty);
        expect(logger.warnings, hasLength(1));
      });
    });

    test('discards a read that completes after the deadline and still writes '
        'nothing', () {
      fakeAsync((async) {
        storage.heldRead = Completer<void>();
        ClientSession? settled;
        settle().then((session) => settled = session);
        async.elapse(const Duration(seconds: 1));
        final fallback = settled;

        storage.heldRead!.complete();
        async.flushMicrotasks();

        expect(settled, same(fallback));
        expect(storage.writes, isEmpty);
      });
    });

    test('keeps the ephemeral instance ID when a stored one arrives after the '
        'deadline', () {
      fakeAsync((async) {
        storage.record = record(createdAt: now());
        storage.heldRead = Completer<void>();
        ClientSession? settled;
        settle().then((session) => settled = session);
        async.elapse(const Duration(seconds: 1));

        storage.heldRead!.complete();
        async.flushMicrotasks();

        expect(settled?.instanceId, isNot(_storedId));
        expect(settled?.ephemeral, isTrue);
      });
    });

    test('falls back to an ephemeral instance ID when the write has not '
        'completed by the deadline', () {
      fakeAsync((async) {
        storage.heldWrite = Completer<void>();
        ClientSession? settled;
        settle().then((session) => settled = session);

        async.elapse(const Duration(seconds: 1));

        expect(settled?.instanceId, matches(uuidV4Pattern));
        expect(settled?.ephemeral, isTrue);
      });
    });

    test(
      'does not warn about the deadline once the storage answered before it',
      () {
        fakeAsync((async) {
          ClientSession? settled;
          settle().then((session) => settled = session);
          async.flushMicrotasks();

          expect(settled?.ephemeral, isFalse);

          async.elapse(const Duration(seconds: 2));

          expect(logger.warnings, isEmpty);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  });
}

final class _ThrowingInstanceIdStorage implements InstanceIdStorage {
  @override
  Future<String?> read() => throw StateError('no plugin');

  @override
  Future<bool> write(String record) => throw StateError('no plugin');
}
