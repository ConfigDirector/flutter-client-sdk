import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../client/client_options.dart';

const String _cachedValuesKeyPrefix = 'configdirector-sdk:cached-values:';
const int _sizeLimitBytes = 256 * 1024;

CachingProvider sharedPreferencesCachingProvider(String clientSdkKey) =>
    _SharedPreferencesCachingProvider(
      _cachedValuesKeyPrefix +
          sha256.convert(utf8.encode(clientSdkKey)).toString(),
    );

final class _SharedPreferencesCachingProvider implements CachingProvider {
  const _SharedPreferencesCachingProvider(this._key);

  final String _key;

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = await preferences.setString(_key, value);
    if (!stored) {
      throw StateError('shared_preferences refused to store the entry');
    }
  }

  @override
  Future<void> remove() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }

  @override
  int sizeLimit() => _sizeLimitBytes;
}
