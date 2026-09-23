import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names the OpenFeature provider at the version it was published', () {
    final identity = SdkIdentity.openFeatureProvider('1.2.3');

    expect(identity.name, 'flutter-openfeature-client-provider');
    expect(identity.version, '1.2.3');
    expect('$identity', 'flutter-openfeature-client-provider/1.2.3');
  });

  test('rejects a blank version', () {
    expect(
      () => SdkIdentity.openFeatureProvider(' '),
      throwsA(isA<ConfigDirectorValidationException>()),
    );
  });
}
