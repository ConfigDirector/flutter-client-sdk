import 'package:configdirector_flutter_client_sdk/src/platform/shared_preferences_caching_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _clientSdkKeyDigest =
    'a436715ed46b2aacdf095eb10a8ed3d532c299456a62595160ebd77bf5be76de';
const String _preferenceKey =
    'configdirector-sdk:cached-values:'
    'a436715ed46b2aacdf095eb10a8ed3d532c299456a62595160ebd77bf5be76de';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads nothing when no entry was kept', () async {
    final provider = sharedPreferencesCachingProvider(_clientSdkKeyDigest);

    expect(await provider.read(), isNull);
  });

  test('reads back the entry it wrote', () async {
    final provider = sharedPreferencesCachingProvider(_clientSdkKeyDigest);

    await provider.write('{"formatVersion":1}');

    expect(await provider.read(), '{"formatVersion":1}');
  });

  test('keeps the entry under the client SDK key digest', () async {
    await sharedPreferencesCachingProvider(
      _clientSdkKeyDigest,
    ).write('{"formatVersion":1}');

    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getString(_preferenceKey), '{"formatVersion":1}');
    expect(preferences.getKeys(), {_preferenceKey});
  });

  test('removes the entry', () async {
    final provider = sharedPreferencesCachingProvider(_clientSdkKeyDigest);
    await provider.write('{"formatVersion":1}');

    await provider.remove();

    expect(await provider.read(), isNull);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('accepts entries of up to 256 KB', () {
    expect(
      sharedPreferencesCachingProvider(_clientSdkKeyDigest).sizeLimit(),
      262144,
    );
  });
}
