/// Flutter client SDK for ConfigDirector, a remote configuration and feature
/// flag service.
///
/// ```dart
/// final client = ConfigDirectorClient(
///   'YOUR-SDK-KEY',
///   options: const ConfigDirectorClientOptions(
///     metadata: ConfigDirectorMetaContext(appName: 'my-app', appVersion: '1.0.0'),
///   ),
/// );
///
/// await client.initialize(const ConfigDirectorContext(id: 'user-123'));
///
/// final darkMode = client.getValue('dark-mode', false);
/// ```
library;

export 'src/client/client_events.dart';
export 'src/client/client_options.dart';
export 'src/client/config_director_client.dart';
export 'src/errors.dart';
export 'src/logger.dart';
export 'src/types.dart'
    hide ConfigSet, ConfigSetKind, ConfigState, ConfigType, SdkMetaContext;
