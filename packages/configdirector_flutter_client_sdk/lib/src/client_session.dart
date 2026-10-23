import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'logger.dart';

final class ClientSession {
  const ClientSession({required this.instanceId, required this.ephemeral});

  ClientSession.provisional()
    : this(instanceId: const Uuid().v4(), ephemeral: true);

  final String instanceId;
  final bool ephemeral;
}

abstract interface class InstanceIdStorage {
  Future<String?> read();

  Future<bool> write(String record);
}

const int _recordVersion = 1;
const Duration _storageDeadline = Duration(seconds: 1);
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

sealed class _StoredInstanceId {
  const _StoredInstanceId();
}

final class _Current extends _StoredInstanceId {
  const _Current(this.instanceId);

  final String instanceId;
}

final class _NothingUsable extends _StoredInstanceId {
  const _NothingUsable();
}

final class _Unreadable extends _StoredInstanceId {
  const _Unreadable();
}

Future<ClientSession> settleClientSession({
  required ClientSession provisional,
  required InstanceIdStorage storage,
  required ConfigDirectorLogger logger,
}) {
  final settled = Completer<ClientSession>();
  final deadline = Timer(_storageDeadline, () {
    logger.warn(
      '[ConfigDirectorClient] The instance ID storage did not respond within '
      '${_storageDeadline.inMilliseconds}ms, so this app start looks like a '
      'new install to ConfigDirector.',
    );
    settled.complete(provisional);
  });

  unawaited(
    _settledFromStorage(
      provisional,
      storage,
      deadlinePassed: () => !deadline.isActive,
      logger: logger,
    ).then((session) {
      if (settled.isCompleted) {
        return;
      }
      deadline.cancel();
      settled.complete(session);
    }),
  );
  return settled.future;
}

Future<ClientSession> _settledFromStorage(
  ClientSession provisional,
  InstanceIdStorage storage, {
  required bool Function() deadlinePassed,
  required ConfigDirectorLogger logger,
}) async {
  final storedInstanceId = await _storedInstanceId(storage, logger);
  switch (storedInstanceId) {
    case _Current(:final instanceId):
      return ClientSession(instanceId: instanceId, ephemeral: false);
    case _Unreadable():
      return provisional;
    case _NothingUsable():
      if (deadlinePassed()) {
        return provisional;
      }
      final stored = await _store(storage, provisional.instanceId, logger);
      return ClientSession(
        instanceId: provisional.instanceId,
        ephemeral: !stored,
      );
  }
}

Future<_StoredInstanceId> _storedInstanceId(
  InstanceIdStorage storage,
  ConfigDirectorLogger logger,
) async {
  final String? raw;
  try {
    raw = await storage.read();
  } on Object catch (error, stackTrace) {
    logger.warn(_couldNot('read'), error, stackTrace);
    return const _Unreadable();
  }
  if (raw == null) {
    return const _NothingUsable();
  }

  final Object? record;
  try {
    record = jsonDecode(raw);
  } on FormatException {
    logger.debug(
      '[ConfigDirectorClient] The stored instance ID is not valid JSON, '
      'generating a new one',
    );
    return const _NothingUsable();
  }

  if (record is! Map<String, Object?>) {
    return _failedValidation(logger);
  }
  final instanceId = record['id'];
  final createdAt = record['createdAt'];
  if (record['v'] != _recordVersion ||
      instanceId is! String ||
      !_uuidV4Pattern.hasMatch(instanceId) ||
      createdAt is! int ||
      createdAt <= 0) {
    return _failedValidation(logger);
  }

  return _Current(instanceId);
}

_StoredInstanceId _failedValidation(ConfigDirectorLogger logger) {
  logger.debug(
    '[ConfigDirectorClient] The stored instance ID failed validation, '
    'generating a new one',
  );
  return const _NothingUsable();
}

Future<bool> _store(
  InstanceIdStorage storage,
  String instanceId,
  ConfigDirectorLogger logger,
) async {
  final record = jsonEncode({
    'v': _recordVersion,
    'id': instanceId,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  });
  final bool stored;
  try {
    stored = await storage.write(record);
  } on Object catch (error, stackTrace) {
    logger.warn(_couldNot('store'), error, stackTrace);
    return false;
  }

  if (!stored) {
    logger.warn(_couldNot('store'));
  }
  return stored;
}

String _couldNot(String action) =>
    '[ConfigDirectorClient] The ConfigDirector SDK could not $action its '
    'instance ID, so this app start looks like a new install to '
    'ConfigDirector.';
