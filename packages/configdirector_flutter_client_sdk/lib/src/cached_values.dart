import 'dart:async';
import 'dart:convert';

import 'client/client_options.dart';
import 'client/connection_plan.dart';
import 'logger.dart';
import 'types.dart';

const int _entryFormatVersion = 1;
const String _defaultContextKind = 'user';

sealed class CachingPlan {
  const CachingPlan();
}

final class KeepValues extends CachingPlan {
  const KeepValues({required this.provider, required this.clientSdkKey});

  final CachingProvider provider;
  final String clientSdkKey;
}

final class KeepNothing extends CachingPlan {
  const KeepNothing();
}

CachingPlan planCaching(
  Connect live,
  CachingOptions caching,
  CachingProvider Function(String clientSdkKey) platformProvider,
) {
  if (!caching.enabled) {
    return const KeepNothing();
  }
  return KeepValues(
    provider: caching.provider ?? platformProvider(live.clientSdkKey),
    clientSdkKey: live.clientSdkKey,
  );
}

sealed class ContextTag {
  const ContextTag(this.contextKind);

  final String contextKind;

  Map<String, Object?> toJson();
}

final class _IdentifiedContextTag extends ContextTag {
  const _IdentifiedContextTag(super.contextKind, this.contextId);

  final String contextId;

  @override
  Map<String, Object?> toJson() => {
    'contextKind': contextKind,
    'contextId': contextId,
  };
}

final class _AnonymousContextTag extends ContextTag {
  const _AnonymousContextTag(super.contextKind, this.anonymousInstanceId);

  final String anonymousInstanceId;

  @override
  Map<String, Object?> toJson() => {
    'contextKind': contextKind,
    'anonymousInstanceId': anonymousInstanceId,
  };
}

ContextTag _contextTagFor(ConfigDirectorContext? context, String instanceId) {
  final contextKind = context?.kind ?? _defaultContextKind;
  final contextId = context?.id;
  if (contextId != null) {
    return _IdentifiedContextTag(contextKind, contextId);
  }
  return _AnonymousContextTag(contextKind, instanceId);
}

bool _sameContextTag(ContextTag stored, ContextTag launch) =>
    switch ((stored, launch)) {
      (_IdentifiedContextTag stored, _IdentifiedContextTag launch) =>
        stored.contextKind == launch.contextKind &&
            stored.contextId == launch.contextId,
      (_AnonymousContextTag stored, _AnonymousContextTag launch) =>
        stored.contextKind == launch.contextKind &&
            stored.anonymousInstanceId == launch.anonymousInstanceId,
      _ => false,
    };

final class CachedValues {
  const CachedValues({
    required this.contextTag,
    required this.environmentId,
    required this.projectId,
    required this.configs,
    required this.receivedAt,
  });

  final ContextTag contextTag;
  final String environmentId;
  final String projectId;
  final Map<String, ConfigState> configs;
  final int receivedAt;
}

sealed class CachedValuesRead {
  const CachedValuesRead();
}

final class CachedValuesStored extends CachedValuesRead {
  const CachedValuesStored(this.cachedValues);

  final CachedValues cachedValues;
}

final class NoCachedValues extends CachedValuesRead {
  const NoCachedValues();
}

final class CachedValuesUnreadable extends CachedValuesRead {
  const CachedValuesUnreadable();
}

final class CachedValuesReadFailed extends CachedValuesRead {
  const CachedValuesReadFailed();
}

enum CachedValuesAdoption {
  adopt('adopted'),
  liveValuesAlreadyArrived('live values already arrived'),
  contextMismatch('the launch context does not match');

  const CachedValuesAdoption(this.description);

  final String description;
}

CachedValuesAdoption decideCachedValuesAdoption(
  CachedValues cachedValues,
  ContextTag launchContextTag, {
  required bool hasReceivedLiveValues,
}) {
  if (hasReceivedLiveValues) {
    return CachedValuesAdoption.liveValuesAlreadyArrived;
  }
  if (!_sameContextTag(cachedValues.contextTag, launchContextTag)) {
    return CachedValuesAdoption.contextMismatch;
  }
  return CachedValuesAdoption.adopt;
}

String _encodeEntry(String clientSdkKey, CachedValues cachedValues) =>
    jsonEncode({
      'formatVersion': _entryFormatVersion,
      'clientSdkKey': clientSdkKey,
      'contextTag': cachedValues.contextTag.toJson(),
      'environmentId': cachedValues.environmentId,
      'projectId': cachedValues.projectId,
      'configs': cachedValues.configs.map(
        (key, config) => MapEntry(key, config.toJson()),
      ),
      'receivedAt': cachedValues.receivedAt,
    });

CachedValues? _decodeEntryFor(String clientSdkKey, String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final contextTag = _decodeContextTag(decoded['contextTag']);
  final configs = _decodeConfigs(decoded['configs']);
  final environmentId = decoded['environmentId'];
  final projectId = decoded['projectId'];
  final receivedAt = decoded['receivedAt'];
  if (decoded['formatVersion'] != _entryFormatVersion ||
      decoded['clientSdkKey'] != clientSdkKey ||
      contextTag == null ||
      configs == null ||
      environmentId is! String ||
      projectId is! String ||
      receivedAt is! int) {
    return null;
  }
  return CachedValues(
    contextTag: contextTag,
    environmentId: environmentId,
    projectId: projectId,
    configs: configs,
    receivedAt: receivedAt,
  );
}

ContextTag? _decodeContextTag(Object? candidate) {
  if (candidate is! Map<String, Object?>) {
    return null;
  }
  final contextKind = candidate['contextKind'];
  final contextId = candidate['contextId'];
  final anonymousInstanceId = candidate['anonymousInstanceId'];
  if (contextKind is! String) {
    return null;
  }
  if (contextId is String) {
    return _IdentifiedContextTag(contextKind, contextId);
  }
  if (anonymousInstanceId is String) {
    return _AnonymousContextTag(contextKind, anonymousInstanceId);
  }
  return null;
}

Map<String, ConfigState>? _decodeConfigs(Object? candidate) {
  if (candidate is! Map<String, Object?>) {
    return null;
  }
  final configs = <String, ConfigState>{};
  for (final MapEntry(:key, :value) in candidate.entries) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        value['key'] is! String) {
      return null;
    }
    configs[key] = ConfigState.fromJson(value);
  }
  return Map.unmodifiable(configs);
}

enum _Warning {
  readFailed,
  unreadable,
  overTheSizeLimit,
  writeFailed,
  removeFailed,
}

final class CachedValuesStore {
  CachedValuesStore({
    required CachingProvider provider,
    required String clientSdkKey,
    required Future<String> instanceId,
    required ConfigDirectorLogger logger,
  }) : _provider = provider,
       _clientSdkKey = clientSdkKey,
       _instanceId = instanceId,
       _logger = logger {
    _pendingRead = _readEntry();
  }

  final CachingProvider _provider;
  final String _clientSdkKey;
  final Future<String> _instanceId;
  final ConfigDirectorLogger _logger;
  final Set<_Warning> _warned = {};

  late final Future<CachedValuesRead> _pendingRead;
  CachedValues? _queuedCachedValues;
  bool _writing = false;

  Future<CachedValuesRead> read() => _pendingRead;

  Future<ContextTag> contextTagOf(ConfigDirectorContext? context) async =>
      _contextTagFor(context, await _instanceId);

  void replace(ConfigDirectorContext? context, ConfigSet configSet) {
    final receivedAt = DateTime.now().millisecondsSinceEpoch;
    unawaited(
      contextTagOf(context).then((contextTag) {
        _queuedCachedValues = CachedValues(
          contextTag: contextTag,
          environmentId: configSet.environmentId,
          projectId: configSet.projectId,
          configs: configSet.configs,
          receivedAt: receivedAt,
        );
        return _writeQueued();
      }),
    );
  }

  Future<CachedValuesRead> _readEntry() async {
    final String? raw;
    try {
      raw = await _provider.read();
    } on Object catch (error, stackTrace) {
      _warnOnce(
        _Warning.readFailed,
        'Could not read the values kept on the device, starting without them.',
        error,
        stackTrace,
      );
      return const CachedValuesReadFailed();
    }
    if (raw == null || raw.isEmpty) {
      return const NoCachedValues();
    }

    final cachedValues = _decodeEntryFor(_clientSdkKey, raw);
    if (cachedValues == null) {
      _warnOnce(
        _Warning.unreadable,
        'The values kept on the device could not be read and were removed, '
        'starting without them.',
      );
      await _removeEntry();
      return const CachedValuesUnreadable();
    }
    return CachedValuesStored(cachedValues);
  }

  Future<void> _writeQueued() async {
    if (_writing) {
      return;
    }
    _writing = true;
    try {
      while (_queuedCachedValues != null) {
        final cachedValues = _queuedCachedValues!;
        _queuedCachedValues = null;
        await _writeEntry(cachedValues);
      }
    } finally {
      _writing = false;
    }
  }

  Future<void> _writeEntry(CachedValues cachedValues) async {
    final serialized = _encodeEntry(_clientSdkKey, cachedValues);
    final size = utf8.encode(serialized).length;
    final limit = _provider.sizeLimit();
    if (size > limit) {
      _warnOnce(
        _Warning.overTheSizeLimit,
        'The values received ($size bytes) exceed the caching provider\'s '
        'limit of $limit bytes, so no values are kept on the device.',
      );
      await _removeEntry();
      return;
    }
    try {
      await _provider.write(serialized);
    } on Object catch (error, stackTrace) {
      _warnOnce(
        _Warning.writeFailed,
        'Could not keep the values on the device.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _removeEntry() async {
    try {
      await _provider.remove();
    } on Object catch (error, stackTrace) {
      _warnOnce(
        _Warning.removeFailed,
        'Could not remove the values kept on the device.',
        error,
        stackTrace,
      );
    }
  }

  void _warnOnce(
    _Warning warning,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (!_warned.add(warning)) {
      return;
    }
    _logger.warn('[ConfigDirectorClient] $message', error, stackTrace);
  }
}
