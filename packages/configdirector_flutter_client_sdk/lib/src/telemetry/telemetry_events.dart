import 'package:flutter/foundation.dart';

import '../types.dart';
import 'telemetry_value.dart';

/// A single config evaluation, as reported to ConfigDirector.
///
/// Instances are handed to a background isolate, so every field is either a
/// primitive, an enum, or another deeply immutable value.
@immutable
final class EvaluatedConfigEvent {
  const EvaluatedConfigEvent({
    required this.key,
    required this.defaultValue,
    required this.evaluatedValue,
    required this.requestedType,
    required this.usedDefault,
    required this.evaluationReason,
    this.contextId,
    this.type,
    this.evaluatedValueId,
  });

  /// Builds the event for an evaluation of [key] that returned
  /// [evaluatedValue].
  factory EvaluatedConfigEvent.fromEvaluation({
    required String key,
    required Object defaultValue,
    required Object evaluatedValue,
    required String requestedType,
    required bool usedDefault,
    required EvaluationReason evaluationReason,
    String? contextId,
    ConfigType? type,
    String? evaluatedValueId,
  }) => EvaluatedConfigEvent(
    key: key,
    defaultValue: TelemetryValue.of(defaultValue, type: type),
    evaluatedValue: TelemetryValue.of(
      evaluatedValue,
      valueId: evaluatedValueId,
      type: type,
    ),
    requestedType: requestedType,
    usedDefault: usedDefault,
    evaluationReason: evaluationReason,
    contextId: contextId,
    type: type,
    evaluatedValueId: evaluatedValueId,
  );

  /// The id of the context the config was evaluated against.
  final String? contextId;

  final String key;

  /// The type the config was declared with, or `null` when no config state was
  /// found for [key].
  final ConfigType? type;

  final TelemetryValue defaultValue;

  /// The name of the type the caller asked the value to be returned as.
  final String requestedType;

  final TelemetryValue evaluatedValue;

  /// The id the server sent for the evaluated value, kept alongside
  /// [evaluatedValue] because a value small enough to report inline is reported
  /// by value.
  final String? evaluatedValueId;

  final bool usedDefault;
  final EvaluationReason evaluationReason;

  /// Returns this event with both of its values reduced to the form that is
  /// sent to the server. See [TelemetryValue.compacted].
  EvaluatedConfigEvent compacted() => EvaluatedConfigEvent(
    key: key,
    defaultValue: defaultValue.compacted(),
    evaluatedValue: evaluatedValue.compacted(),
    requestedType: requestedType,
    usedDefault: usedDefault,
    evaluationReason: evaluationReason,
    contextId: contextId,
    type: type,
    evaluatedValueId: evaluatedValueId,
  );

  Map<String, Object?> toJson() => {
    if (contextId != null) 'contextId': contextId,
    'key': key,
    if (type != null) 'type': type!.wireName,
    'defaultValue': defaultValue.toJson(),
    'requestedType': requestedType,
    'evaluatedValue': evaluatedValue.toJson(),
    if (evaluatedValueId != null) 'evaluatedValueId': evaluatedValueId,
    'usedDefault': usedDefault,
    'evaluationReason': evaluationReason.wireName,
  };

  /// Identical evaluations are reported once with a count, so equality is what
  /// decides which events collapse together.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EvaluatedConfigEvent &&
          other.contextId == contextId &&
          other.key == key &&
          other.type == type &&
          other.defaultValue == defaultValue &&
          other.requestedType == requestedType &&
          other.evaluatedValue == evaluatedValue &&
          other.evaluatedValueId == evaluatedValueId &&
          other.usedDefault == usedDefault &&
          other.evaluationReason == evaluationReason);

  @override
  int get hashCode => Object.hash(
    contextId,
    key,
    type,
    defaultValue,
    requestedType,
    evaluatedValue,
    evaluatedValueId,
    usedDefault,
    evaluationReason,
  );

  @override
  String toString() =>
      'EvaluatedConfigEvent(key: $key, evaluatedValue: $evaluatedValue, '
      'usedDefault: $usedDefault, reason: ${evaluationReason.wireName})';
}

/// The name reported for the type a caller asked a config to be returned as.
///
/// Dispatches on `T` rather than on the runtime type of [defaultValue] because
/// on the web every number is a double at runtime, which would report an `int`
/// default as a `double`.
String requestedTypeOf<T extends Object>(T defaultValue) {
  if (T == String) {
    return 'String';
  }
  if (T == bool) {
    return 'bool';
  }
  if (T == int) {
    return 'int';
  }
  if (T == double) {
    return 'double';
  }
  if (T == num) {
    return 'num';
  }

  return switch (defaultValue) {
    String() => 'String',
    bool() => 'bool',
    int() => 'int',
    double() => 'double',
    Map() => 'Map',
    List() => 'List',
    _ => defaultValue.runtimeType.toString(),
  };
}
