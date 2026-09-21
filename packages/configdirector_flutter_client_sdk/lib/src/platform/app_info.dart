import 'package:package_info_plus/package_info_plus.dart';

import '../types.dart';

/// Reads the name and version of the running application. Injectable for
/// testing.
typedef AppInfoResolver = Future<ConfigDirectorMetaContext> Function();

/// Reads the name and version the platform reports for the running application.
///
/// The values come from the application label and `versionName` on Android,
/// from `CFBundleDisplayName`/`CFBundleName` and `CFBundleShortVersionString`
/// on iOS and macOS, and from the generated `version.json` on web. A field is
/// `null` when the platform reports it blank.
Future<ConfigDirectorMetaContext> resolveAppInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();
  return ConfigDirectorMetaContext(
    appName: _nullIfBlank(packageInfo.appName),
    appVersion: _nullIfBlank(packageInfo.version),
  );
}

String? _nullIfBlank(String value) => value.trim().isEmpty ? null : value;
