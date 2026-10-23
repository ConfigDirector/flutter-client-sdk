import 'package:configdirector_flutter_client_sdk/src/client_session.dart';
import 'package:configdirector_flutter_client_sdk/src/platform/instance_id_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

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

  test('reuses the instance ID an earlier version of the SDK stored', () async {
    const storedByEarlierVersion =
        '{"v":1,"id":"22222222-2222-4222-8222-222222222222",'
        '"createdAt":1760000000000}';
    SharedPreferences.setMockInitialValues({
      'configdirector-sdk:instance-id': storedByEarlierVersion,
    });

    final session = await settleClientSession(
      provisional: ClientSession.provisional(),
      storage: sharedPreferencesInstanceIdStorage(),
      logger: RecordingLogger(),
    );

    final preferences = await SharedPreferences.getInstance();

    expect(session.instanceId, '22222222-2222-4222-8222-222222222222');
    expect(session.ephemeral, isFalse);
    expect(
      preferences.getString('configdirector-sdk:instance-id'),
      storedByEarlierVersion,
    );
  });
}
