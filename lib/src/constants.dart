/// The default base URL of the ConfigDirector client SDK API.
final Uri clientBaseUrl = Uri.parse(
  'https://client-sdk-api.configdirector.com',
);

/// The name this SDK identifies itself with to the ConfigDirector server.
const String sdkName = 'flutter-client-sdk';

/// The version of this SDK.
///
/// Kept in sync with the `version` field in `pubspec.yaml`: run
/// `dart run tool/update_sdk_version.dart` after bumping it. The
/// `version_sync_test.dart` test fails if the two ever drift apart.
const String sdkVersion = '0.10.0';
