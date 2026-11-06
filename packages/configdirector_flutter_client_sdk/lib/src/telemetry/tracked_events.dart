import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../types.dart';

const int trackedEventsPerBatch = 1000;
const int _nameMaximumCharacters = 150;
const int _detailsMaximumTopLevelKeys = 20;
const int _detailsMaximumJsonBytes = 1024;
const String _userContextKind = 'user';

@immutable
final class TrackedEventEntry {
  const TrackedEventEntry({
    required this.name,
    required this.happenedAt,
    this.contextKind,
    this.contextIdentifier,
    this.value,
    this.details,
  });

  final String name;
  final String? contextKind;
  final String? contextIdentifier;
  final num? value;
  final TrackedEventDetails? details;
  final String happenedAt;

  Map<String, Object?> toJson() => {
    'name': name,
    if (contextKind != null) 'contextKind': contextKind,
    if (contextIdentifier != null) 'contextIdentifier': contextIdentifier,
    if (value != null) 'value': value,
    if (details != null) 'details': details,
    'happenedAt': happenedAt,
  };
}

enum TrackedEventWarning {
  nameOutsideTheCharacterLimit(
    '[ConfigDirectorClient] A tracked event was not reported because its name '
    'does not have 1 to $_nameMaximumCharacters characters.',
  ),
  valueNotAFiniteNumber(
    '[ConfigDirectorClient] A tracked event was reported without its value '
    'because the value is not a finite number.',
  ),
  detailsNotReportable(
    '[ConfigDirectorClient] A tracked event was reported without its details '
    'because they have more than $_detailsMaximumTopLevelKeys top-level keys, '
    'are larger than $_detailsMaximumJsonBytes bytes as JSON, or cannot be '
    'written as JSON.',
  ),
  batchAlreadyFull(
    '[ConfigDirectorClient] A tracked event was not reported because '
    '$trackedEventsPerBatch tracked events are already waiting for the next '
    'telemetry batch.',
  );

  const TrackedEventWarning(this.message);

  final String message;
}

sealed class TrackedEventAdmission {
  const TrackedEventAdmission(this.warnings);

  final List<TrackedEventWarning> warnings;
}

final class TrackedEventAdmitted extends TrackedEventAdmission {
  const TrackedEventAdmitted(this.entry, super.warnings);

  final TrackedEventEntry entry;
}

final class TrackedEventDropped extends TrackedEventAdmission {
  const TrackedEventDropped(super.warnings);
}

TrackedEventAdmission admitTrackedEvent({
  required String name,
  required ConfigDirectorContext? context,
  required TrackOptions? options,
  required DateTime happenedAt,
}) {
  if (!_isWithinTheCharacterLimit(name)) {
    return const TrackedEventDropped([
      TrackedEventWarning.nameOutsideTheCharacterLimit,
    ]);
  }

  final reportedContext = _reportedContextOf(context);
  final (value, valueWarning) = _reportableValueOf(options?.value);
  final (details, detailsWarning) = _reportableDetailsOf(options?.details);
  return TrackedEventAdmitted(
    TrackedEventEntry(
      name: name,
      contextKind: reportedContext?.kind,
      contextIdentifier: reportedContext?.identifier,
      value: value,
      details: details,
      happenedAt: happenedAt.toUtc().toIso8601String(),
    ),
    [valueWarning, detailsWarning].nonNulls.toList(),
  );
}

bool _isWithinTheCharacterLimit(String name) =>
    name.isNotEmpty && name.runes.length <= _nameMaximumCharacters;

({String kind, String identifier})? _reportedContextOf(
  ConfigDirectorContext? context,
) {
  final identifier = context?.anonymous == true ? null : context?.id;
  return identifier == null
      ? null
      : (kind: context?.kind ?? _userContextKind, identifier: identifier);
}

(num?, TrackedEventWarning?) _reportableValueOf(num? value) =>
    value == null || value.isFinite
    ? (value, null)
    : (null, TrackedEventWarning.valueNotAFiniteNumber);

(TrackedEventDetails?, TrackedEventWarning?) _reportableDetailsOf(
  TrackedEventDetails? details,
) {
  if (details == null) {
    return (null, null);
  }

  final jsonCopy = _jsonCopyWithinTheLimits(details);
  return jsonCopy == null
      ? (null, TrackedEventWarning.detailsNotReportable)
      : (jsonCopy, null);
}

TrackedEventDetails? _jsonCopyWithinTheLimits(TrackedEventDetails details) {
  try {
    if (details.length > _detailsMaximumTopLevelKeys) {
      return null;
    }

    final copy = _jsonFormOf(details)! as TrackedEventDetails;
    final jsonBytes = utf8.encode(jsonEncode(copy)).length;
    return jsonBytes > _detailsMaximumJsonBytes ? null : copy;
  } on Object {
    return null;
  }
}

Object? _jsonFormOf(Object? value) => switch (value) {
  null || bool() || String() || num(isFinite: true) => value,
  num() => null,
  DateTime() => value.toUtc().toIso8601String(),
  List() => [for (final item in value) _jsonFormOf(item)],
  Map() => <String, Object?>{
    for (final entry in value.entries)
      entry.key as String: _jsonFormOf(entry.value),
  },
  _ => _jsonFormOf((value as dynamic).toJson()),
};
