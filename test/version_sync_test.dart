// Reads `pubspec.yaml` from disk, so it only runs where `dart:io` works.
@TestOn('vm')
library;

import 'dart:io';

import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sdkVersion matches the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason: 'Tests are expected to run from the package root.',
    );

    final version = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync())?.group(1);

    expect(
      constants.sdkVersion,
      version,
      reason:
          'Run `dart run tool/update_sdk_version.dart` to sync the constant.',
    );
  });
}
