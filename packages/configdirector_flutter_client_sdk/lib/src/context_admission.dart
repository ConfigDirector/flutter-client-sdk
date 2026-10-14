import 'types.dart';

const int _contextKindMaximumLength = 64;
const int _contextKindSampleMaximumCharacters = 128;

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

ContextAdmission admissionOf(ConfigDirectorContext? context) {
  final contextKind = context?.kind;
  if (contextKind == null || _isValidContextKind(contextKind)) {
    return ContextAdmitted(context);
  }

  return ContextIgnoredForAnInvalidContextKind(
    _firstCharactersOf(contextKind, _contextKindSampleMaximumCharacters),
  );
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
