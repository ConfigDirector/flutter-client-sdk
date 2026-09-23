library;

import 'src/client/client_options.dart';
import 'src/client/config_director_client.dart';
import 'src/client/default_config_director_client.dart';
import 'src/sdk_identity.dart';

export 'src/sdk_identity.dart' show SdkIdentity;

ConfigDirectorClient createWrapperClient({
  required String clientSdkKey,
  required SdkIdentity identity,
  ConfigDirectorClientOptions? options,
}) => DefaultConfigDirectorClient(
  clientSdkKey,
  options: options,
  identity: identity,
);
