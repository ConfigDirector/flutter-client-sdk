import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'types.dart';

/// The result of parsing a [ConfigState] into the type requested by the caller.
@immutable
final class ConfigEvaluationResult<T extends Object> {
  const ConfigEvaluationResult({
    required this.value,
    required this.usedDefault,
    required this.reason,
    this.valueId,
  });

  final T value;
  final String? valueId;
  final bool usedDefault;
  final EvaluationReason reason;
}

/// Config types a boolean can be parsed from.
const Set<ConfigType> _booleanSourceTypes = {
  ConfigType.boolean,
  ConfigType.string,
  ConfigType.custom,
};

/// Config types a number can be parsed from.
const Set<ConfigType> _numericSourceTypes = {
  ConfigType.integer,
  ConfigType.float,
  ConfigType.enumeration,
  ConfigType.string,
  ConfigType.custom,
};

/// Parses [configState]'s value into the type of [defaultValue], falling back to
/// [defaultValue] whenever the value is absent or cannot be represented as that
/// type.
ConfigEvaluationResult<T> parseConfigValue<T extends Object>(
  ConfigState configState,
  T defaultValue,
) {
  final rawValue = configState.value;
  if (rawValue == null || rawValue.isEmpty) {
    return _useDefault(defaultValue, EvaluationReason.valueMissing);
  }

  if (configState.type == ConfigType.json) {
    return _parseJson(rawValue, defaultValue, configState.valueId);
  }

  // Every config value is a string on the wire, so a string default always
  // matches regardless of the config's declared type.
  if (defaultValue is String) {
    return _matched(rawValue, configState.valueId, defaultValue);
  }

  if (defaultValue is bool) {
    if (!_booleanSourceTypes.contains(configState.type)) {
      return _useDefault(defaultValue, EvaluationReason.typeMismatch);
    }
    final parsed = _parseBool(rawValue);
    return parsed == null
        ? _useDefault(defaultValue, EvaluationReason.invalidBoolean)
        : _matched(parsed, configState.valueId, defaultValue);
  }

  if (defaultValue is num) {
    if (!_numericSourceTypes.contains(configState.type)) {
      return _useDefault(defaultValue, EvaluationReason.typeMismatch);
    }
    // Dispatch on `T` rather than on the runtime type of [defaultValue]: on the
    // web every number is a JavaScript double, so `0.0 is int` is true there
    // and a `double` default would otherwise be truncated. A `num` default
    // falls through to the double branch, which any numeric value satisfies.
    final parsed = T == int ? _parseInt(rawValue) : _parseDouble(rawValue);
    return parsed == null
        ? _useDefault(defaultValue, EvaluationReason.invalidNumber)
        : _matched(parsed, configState.valueId, defaultValue);
  }

  // Structured defaults (maps, lists) can only come from a JSON config.
  return _useDefault(defaultValue, EvaluationReason.typeMismatch);
}

ConfigEvaluationResult<T> _parseJson<T extends Object>(
  String rawValue,
  T defaultValue,
  String? valueId,
) {
  // A string default asks for the raw JSON document rather than a decoded one.
  if (defaultValue is String) {
    return _matched(rawValue, valueId, defaultValue);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(rawValue);
  } on FormatException {
    return _useDefault(defaultValue, EvaluationReason.invalidJson);
  }

  if (decoded == null) {
    return _useDefault(defaultValue, EvaluationReason.invalidJson);
  }

  return _matched(decoded, valueId, defaultValue);
}

/// Returns a match when [parsed] is assignable to `T`, and a type mismatch
/// otherwise. Keeps every parsing branch from having to cast unsafely.
ConfigEvaluationResult<T> _matched<T extends Object>(
  Object parsed,
  String? valueId,
  T defaultValue,
) {
  if (parsed is! T) {
    return _useDefault(defaultValue, EvaluationReason.typeMismatch);
  }

  return ConfigEvaluationResult(
    value: parsed,
    valueId: valueId,
    usedDefault: false,
    reason: EvaluationReason.foundMatch,
  );
}

ConfigEvaluationResult<T> _useDefault<T extends Object>(
  T defaultValue,
  EvaluationReason reason,
) => ConfigEvaluationResult(
  value: defaultValue,
  usedDefault: true,
  reason: reason,
);

bool? _parseBool(String value) => switch (value.toLowerCase()) {
  'true' => true,
  'false' => false,
  _ => null,
};

/// Parses an integer, truncating values written as decimals so that a float
/// config can still serve an `int` default.
int? _parseInt(String value) =>
    int.tryParse(value) ?? _parseDouble(value)?.truncate();

double? _parseDouble(String value) {
  final parsed = double.tryParse(value);
  return parsed == null || !parsed.isFinite ? null : parsed;
}
