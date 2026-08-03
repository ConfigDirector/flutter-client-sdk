import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../types.dart';
import 'value_id.dart';

/// Values longer than this are reported by id rather than inline, to keep
/// telemetry payloads small.
const int configValueMaxLength = 500;

/// A config value as it is reported to ConfigDirector: either the value itself,
/// when it is small enough to send, or the id ConfigDirector knows it by.
@immutable
final class TelemetryValue {
  const TelemetryValue({this.value, this.valueId, this.type});

  /// Builds the reportable form of an evaluated or default config value.
  ///
  /// [valueId] is the id the server sent along with the config state, when
  /// there is one, and [type] the type the config was declared with.
  factory TelemetryValue.of(
    Object? value, {
    String? valueId,
    ConfigType? type,
  }) {
    if (_isJson(value, type)) {
      if (valueId != null) {
        return TelemetryValue(valueId: valueId, type: ConfigType.json);
      }

      final String encoded;
      try {
        encoded = jsonEncode(value);
      } on Object {
        // Values that cannot be encoded are still worth counting, so fall back
        // to whatever the value describes itself as.
        return TelemetryValue(value: value.toString(), type: ConfigType.json);
      }
      return TelemetryValue(value: encoded, type: ConfigType.json);
    }

    final stringValue = value?.toString();
    if (stringValue != null && stringValue.length <= configValueMaxLength) {
      return TelemetryValue(value: stringValue);
    }

    return valueId != null
        ? TelemetryValue(valueId: valueId)
        : TelemetryValue(value: stringValue);
  }

  /// The value serialized as a string, when it is reported inline.
  final String? value;

  /// The id the value is reported by, when it is not reported inline.
  final String? valueId;

  /// The type the config was declared with, carried only until the value is
  /// [compacted].
  final ConfigType? type;

  /// Returns the form of this value that is sent to the server: values that are
  /// too large to report inline, and every JSON document, are replaced by their
  /// id.
  ///
  /// This is the only step that hashes, which is why it runs off the main
  /// thread.
  TelemetryValue compacted() {
    if (valueId != null) {
      return TelemetryValue(valueId: valueId);
    }

    final value = this.value;
    if (value != null && value.isNotEmpty) {
      if (value.length <= configValueMaxLength && type != ConfigType.json) {
        return TelemetryValue(value: value);
      }
      return TelemetryValue(valueId: generateValueId(value));
    }

    return this;
  }

  Map<String, Object?> toJson() => {
    if (value != null) 'value': value,
    if (valueId != null) 'valueId': valueId,
    if (type != null) 'type': type!.wireName,
  };

  static bool _isJson(Object? value, ConfigType? type) =>
      type == ConfigType.json ||
      (type == null && (value is Map || value is List));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TelemetryValue &&
          other.value == value &&
          other.valueId == valueId &&
          other.type == type);

  @override
  int get hashCode => Object.hash(value, valueId, type);

  @override
  String toString() =>
      'TelemetryValue(value: $value, valueId: $valueId, type: ${type?.wireName})';
}
