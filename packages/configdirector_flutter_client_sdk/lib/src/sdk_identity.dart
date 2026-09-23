import 'constants.dart' as constants;
import 'errors.dart';

final class SdkIdentity {
  const SdkIdentity._(this.name, this.version);

  factory SdkIdentity.openFeatureProvider(String version) {
    if (version.trim().isEmpty) {
      throw const ConfigDirectorValidationException(
        'No version was provided for the OpenFeature provider. The identity it '
        'reports to the server cannot be built without one.',
      );
    }
    return SdkIdentity._('flutter-openfeature-client-provider', version);
  }

  final String name;
  final String version;

  @override
  String toString() => '$name/$version';
}

const SdkIdentity flutterClientSdkIdentity = SdkIdentity._(
  constants.sdkName,
  constants.sdkVersion,
);
