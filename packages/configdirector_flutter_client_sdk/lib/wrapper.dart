/// The API through which a wrapper maintained by ConfigDirector, such as the
/// OpenFeature provider, reports its own name and version to the server in
/// place of this SDK's.
///
/// An application has no use for it, which is why it is a separate library
/// rather than part of `configdirector_flutter_client_sdk.dart`.
library;

import 'src/client/client_options.dart';
import 'src/client/config_director_client.dart';
import 'src/client/default_config_director_client.dart';
import 'src/sdk_identity.dart';

export 'src/sdk_identity.dart' show SdkIdentity;

/// Creates a [ConfigDirectorClient] that reports [identity] to the server
/// instead of this SDK's own name and version. Otherwise identical to the
/// [ConfigDirectorClient] constructor.
///
/// Throws a [ConfigDirectorValidationException] if [clientSdkKey] is blank.
ConfigDirectorClient createWrapperClient({
  required String clientSdkKey,
  required SdkIdentity identity,
  ConfigDirectorClientOptions? options,
}) => DefaultConfigDirectorClient(
  clientSdkKey,
  options: options,
  identity: identity,
);
