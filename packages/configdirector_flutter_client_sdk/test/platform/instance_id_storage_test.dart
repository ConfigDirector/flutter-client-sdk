import 'package:configdirector_flutter_client_sdk/src/platform/instance_id_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _record = '{"v":1,"id":"an-id","createdAt":1}';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads nothing when no instance ID was stored', () async {
    final storage = sharedPreferencesInstanceIdStorage();

    expect(await storage.read(), isNull);
  });

  test('reads back the record it stored', () async {
    final storage = sharedPreferencesInstanceIdStorage();

    final stored = await storage.write(_record);

    expect(stored, isTrue);
    expect(await storage.read(), _record);
  });

  test('keeps the record in shared preferences under the SDK key', () async {
    await sharedPreferencesInstanceIdStorage().write(_record);

    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getString('configdirector-sdk:instance-id'), _record);
  });
}
