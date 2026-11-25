import 'dart:convert';

import 'telemetry/telemetry_events.dart';
import 'types.dart';

const int _contextKindMaximumLength = 64;
const int _contextKindSampleMaximumCharacters = 128;
const int _identifierMaximumCharacters = 256;
const int _nameMaximumCharacters = 256;
const int _traitsMaximumJsonBytes = 65536;

const int _lowercaseA = 0x61;
const int _lowercaseZ = 0x7a;
const int _digitZero = 0x30;
const int _digitNine = 0x39;
const int _dash = 0x2d;
const int _underscore = 0x5f;

sealed class ContextAdmission {
  const ContextAdmission();
}

final class ContextAdmitted extends ContextAdmission {
  const ContextAdmitted(this.context);

  final ConfigDirectorContext? context;
}

final class ContextIgnoredForAnInvalidContextKind extends ContextAdmission {
  const ContextIgnoredForAnInvalidContextKind(this.contextKindSample);

  final String contextKindSample;
}

final class ContextIgnoredOverASizeLimit extends ContextAdmission {
  const ContextIgnoredOverASizeLimit(this.reason);

  final ContextSizeLimitReason reason;
}

ContextAdmission admissionOf(ConfigDirectorContext? context) {
  final contextKind = context?.kind;
  if (contextKind != null && !_isValidContextKind(contextKind)) {
    return ContextIgnoredForAnInvalidContextKind(
      _firstCharactersOf(contextKind, _contextKindSampleMaximumCharacters),
    );
  }

  return switch (_firstSizeLimitPassedBy(context)) {
    final reason? => ContextIgnoredOverASizeLimit(reason),
    null => ContextAdmitted(context),
  };
}

ContextSizeLimitReason? _firstSizeLimitPassedBy(
  ConfigDirectorContext? context,
) {
  if (_hasMoreCharactersThan(_identifierMaximumCharacters, context?.id)) {
    return ContextSizeLimitReason.identifierTooLong;
  }
  if (_hasMoreCharactersThan(_nameMaximumCharacters, context?.name)) {
    return ContextSizeLimitReason.nameTooLong;
  }
  if (_hasMoreJsonBytesThan(_traitsMaximumJsonBytes, context?.traits)) {
    return ContextSizeLimitReason.traitsTooLarge;
  }
  return null;
}

bool _hasMoreCharactersThan(int maximumCharacters, String? text) =>
    text != null && text.runes.length > maximumCharacters;

bool _hasMoreJsonBytesThan(int maximumBytes, Map<String, Object?>? traits) {
  if (traits == null) {
    return false;
  }

  final String json;
  try {
    json = jsonEncode(traits);
  } on JsonUnsupportedObjectError {
    return false;
  }
  return utf8.encode(json).length > maximumBytes;
}

bool _isValidContextKind(String contextKind) =>
    contextKind.isNotEmpty &&
    contextKind.length <= _contextKindMaximumLength &&
    contextKind.codeUnits.every(_isContextKindCharacter);

bool _isContextKindCharacter(int codeUnit) =>
    (codeUnit >= _lowercaseA && codeUnit <= _lowercaseZ) ||
    (codeUnit >= _digitZero && codeUnit <= _digitNine) ||
    codeUnit == _dash ||
    codeUnit == _underscore;

String _firstCharactersOf(String text, int maximumCharacters) =>
    String.fromCharCodes(text.runes.take(maximumCharacters));
