import 'dart:io';

/// Reads the top-level `version` field from `pubspec.yaml`.
///
/// Uses a narrow regular expression rather than a YAML parser so that both the
/// generator and the sync test stay dependency-free.
String readPubspecVersion({String path = 'pubspec.yaml'}) {
  final pubspec = File(path);
  if (!pubspec.existsSync()) {
    throw StateError(
      'Could not find ${pubspec.absolute.path}. Run this from the package root.',
    );
  }

  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) {
    throw StateError('No top-level `version` field found in ${pubspec.path}.');
  }

  return match.group(1)!;
}
