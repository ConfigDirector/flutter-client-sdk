/// Rewrites the `sdkVersion` constant in `lib/src/constants.dart` so that it
/// matches the `version` field in `pubspec.yaml`.
///
/// Run from the package root after bumping the version:
///
/// ```sh
/// dart run tool/update_sdk_version.dart
/// ```
library;

import 'dart:io';

import 'pubspec_version.dart';

const String _constantsPath = 'lib/src/constants.dart';

final RegExp _sdkVersionLine = RegExp(
  r"^const String sdkVersion = '[^']*';$",
  multiLine: true,
);

void main() {
  final version = readPubspecVersion();
  final constants = File(_constantsPath);
  final source = constants.readAsStringSync();

  if (!_sdkVersionLine.hasMatch(source)) {
    stderr.writeln(
      'Could not find the `sdkVersion` declaration in $_constantsPath. '
      'Did its formatting change?',
    );
    exit(1);
  }

  final updated = source.replaceFirst(
    _sdkVersionLine,
    "const String sdkVersion = '$version';",
  );

  if (updated == source) {
    stdout.writeln('sdkVersion is already $version.');
    return;
  }

  constants.writeAsStringSync(updated);
  stdout.writeln('Updated sdkVersion to $version in $_constantsPath.');
}
