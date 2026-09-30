import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../errors.dart';
import '../telemetry/value_id.dart';
import '../types.dart';

const int _maxSafeInteger = 9007199254740991;

ConfigState encodeTestValue(String key, Object? value) {
  if (key.trim().isEmpty) {
    throw ConfigDirectorValidationException(
      "Invalid config key '$key'. The key must not be blank.",
    );
  }

  final (type, text) = _encode(key, value);
  return ConfigState(
    id: const Uuid().v4(),
    key: key,
    type: type,
    value: text,
    valueId: generateValueId(text),
  );
}

(ConfigType, String) _encode(String key, Object? value) => switch (value) {
  null => throw ConfigDirectorValidationException(
    "Invalid value for '$key'. The value must not be null; call removeValue "
    'to remove a config.',
  ),
  bool() => (ConfigType.boolean, value.toString()),
  num() when !value.isFinite => throw _nonFinite(key),
  int() => (ConfigType.integer, _encodeInteger(key, value)),
  double() => (ConfigType.float, expandExponent(value.toString())),
  String() => (ConfigType.string, value),
  Map() || List() => (ConfigType.json, _encodeJson(key, value)),
  _ => throw ConfigDirectorValidationException(
    "Invalid value for '$key' of type ${value.runtimeType}. A value must be a "
    'bool, an int, a double, a String, a Map with String keys, or a List.',
  ),
};

String _encodeInteger(String key, int value) {
  _rejectUnsafeInteger(key, value);
  return value.toString();
}

void _rejectUnsafeInteger(String key, int value) {
  if (kIsWeb && (value > _maxSafeInteger || value < -_maxSafeInteger)) {
    throw ConfigDirectorValidationException(
      "Invalid value for '$key'. On the web, an integer must be between "
      '-$_maxSafeInteger and $_maxSafeInteger to be represented exactly.',
    );
  }
}

String _encodeJson(String key, Object value) {
  _validateJsonValue(key, value);
  return jsonEncode(value);
}

void _validateJsonValue(String key, Object? value) {
  switch (value) {
    case null || bool() || String():
      return;
    case num() when !value.isFinite:
      throw _nonFinite(key);
    case int():
      _rejectUnsafeInteger(key, value);
    case double():
      return;
    case Map():
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ConfigDirectorValidationException(
            "Invalid value for '$key'. Every key of a JSON object must be a "
            'String, found ${entry.key.runtimeType}.',
          );
        }
        _validateJsonValue(key, entry.value);
      }
    case List():
      for (final element in value) {
        _validateJsonValue(key, element);
      }
    default:
      throw ConfigDirectorValidationException(
        "Invalid value for '$key'. A JSON document may only contain null, "
        'bool, int, double, String, Map with String keys, and List values, '
        'found ${value.runtimeType}.',
      );
  }
}

ConfigDirectorValidationException _nonFinite(String key) =>
    ConfigDirectorValidationException(
      "Invalid value for '$key'. A number must be finite.",
    );

String expandExponent(String text) {
  final exponentIndex = text.indexOf('e');
  if (exponentIndex < 0) {
    return text;
  }

  final exponent = int.parse(text.substring(exponentIndex + 1));
  var mantissa = text.substring(0, exponentIndex);
  final negative = mantissa.startsWith('-');
  if (negative) {
    mantissa = mantissa.substring(1);
  }

  final pointIndex = mantissa.indexOf('.');
  final digits = mantissa.replaceFirst('.', '');
  final integerDigits =
      (pointIndex < 0 ? mantissa.length : pointIndex) + exponent;

  final String plain;
  if (integerDigits <= 0) {
    plain = '0.${'0' * -integerDigits}$digits';
  } else if (integerDigits >= digits.length) {
    plain = '$digits${'0' * (integerDigits - digits.length)}.0';
  } else {
    plain =
        '${digits.substring(0, integerDigits)}.${digits.substring(integerDigits)}';
  }
  return negative ? '-$plain' : plain;
}
