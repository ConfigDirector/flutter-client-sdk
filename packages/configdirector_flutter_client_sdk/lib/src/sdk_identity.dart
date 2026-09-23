import 'constants.dart' as constants;
import 'errors.dart';

/// The name and version a ConfigDirector wrapper reports to the server in
/// place of this SDK's own, so that the server's SDK usage tells the wrapper
/// apart from applications on the SDK directly.
///
/// Only wrappers maintained by ConfigDirector are represented, which is why
/// there is a factory per wrapper taking its version and no way to build one
/// from an arbitrary name. Hand it to [createWrapperClient].
final class SdkIdentity {
  const SdkIdentity._(this.name, this.version);

  /// The ConfigDirector OpenFeature provider for Flutter, published as
  /// [version].
  ///
  /// Throws a [ConfigDirectorValidationException] if [version] is blank.
  factory SdkIdentity.openFeatureProvider(String version) {
    if (version.trim().isEmpty) {
      throw const ConfigDirectorValidationException(
        'No version was provided for the OpenFeature provider. The identity it '
        'reports to the server cannot be built without one.',
      );
    }
    return SdkIdentity._('flutter-openfeature-client-provider', version);
  }

  /// What the wrapper is called in the server's SDK usage.
  final String name;

  /// The version the wrapper is published under.
  final String version;

  @override
  String toString() => '$name/$version';
}

const SdkIdentity flutterClientSdkIdentity = SdkIdentity._(
  constants.sdkName,
  constants.sdkVersion,
);
