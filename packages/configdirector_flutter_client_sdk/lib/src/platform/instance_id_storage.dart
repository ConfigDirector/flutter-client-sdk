import 'package:shared_preferences/shared_preferences.dart';

import '../client_session.dart';

const String _instanceIdKey = 'configdirector-sdk:instance-id';

InstanceIdStorage sharedPreferencesInstanceIdStorage() =>
    const _SharedPreferencesInstanceIdStorage();

final class _SharedPreferencesInstanceIdStorage implements InstanceIdStorage {
  const _SharedPreferencesInstanceIdStorage();

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_instanceIdKey);
  }

  @override
  Future<bool> write(String record) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(_instanceIdKey, record);
  }
}
