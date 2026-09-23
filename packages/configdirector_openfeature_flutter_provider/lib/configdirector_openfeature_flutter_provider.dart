/// OpenFeature provider for ConfigDirector, a remote configuration and feature
/// flag service, on Flutter.
///
/// ```dart
/// await OpenFeatureAPI.instance.setProviderAndWait(
///   ConfigDirectorProvider(clientSdkKey: 'YOUR-CLIENT-SDK-KEY'),
/// );
///
/// final client = OpenFeatureAPI.instance.getClient();
/// final darkMode = client.getBooleanValue('dark-mode', false);
/// ```
///
/// The types that configure the underlying ConfigDirector client are exported
/// from here as well, so configuring the provider needs no second import.
library;

export 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart'
    show
        ConfigDirectorClient,
        ConfigDirectorClientOptions,
        ConfigDirectorLogLevel,
        ConfigDirectorLogger,
        ConfigDirectorMetaContext,
        ConnectionMode,
        ConnectionOptions,
        ConsoleLogger,
        LogMessageDecorator;

export 'src/config_director_provider.dart' show ConfigDirectorProvider;
