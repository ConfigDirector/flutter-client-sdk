/// Rewrites the `sdkVersion` constant in `lib/src/constants.dart` so that it
/// matches the `version` field in `pubspec.yaml`.
///
/// Run from the package root after bumping the version:
///
/// ```sh
/// dart run tool/update_sdk_version.dart
/// ```
///
/// `test/version_sync_test.dart` fails when the two drift apart. It reads the
/// pubspec itself rather than sharing code with this script, so that a bug in
/// the parsing below cannot hide the drift it is meant to catch.
library;

import 'dart:io';

const String _constantsPath = 'lib/src/constants.dart';

final RegExp _sdkVersionLine = RegExp(
  r"^const String sdkVersion = '[^']*';$",
  multiLine: true,
);

void main() {
  final version = _pubspecVersion();
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

/// Reads the top-level `version` field from `pubspec.yaml`.
///
/// A narrow regular expression keeps this script free of a YAML dependency.
String _pubspecVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln(
      'Could not find ${pubspec.absolute.path}. Run this from the package root.',
    );
    exit(1);
  }

  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    stderr.writeln('No top-level `version` field found in ${pubspec.path}.');
    exit(1);
  }

  return match.group(1)!;
}
