import 'package:configdirector_flutter_client_sdk/src/constants.dart'
    as constants;
import 'package:flutter_test/flutter_test.dart';

import '../tool/pubspec_version.dart';

void main() {
  test('sdkVersion matches the version in pubspec.yaml', () {
    expect(
      constants.sdkVersion,
      readPubspecVersion(),
      reason:
          'Run `dart run tool/update_sdk_version.dart` to sync the constant.',
    );
  });
}
