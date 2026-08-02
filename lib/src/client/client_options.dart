import 'package:flutter/foundation.dart';

import '../logger.dart';
import '../types.dart';

/// How the client connects to the ConfigDirector server.
@immutable
final class ConnectionOptions {
  const ConnectionOptions({
    this.mode = ConnectionMode.streaming,
    this.pollingInterval = const Duration(seconds: 60),
    this.timeout = const Duration(seconds: 3),
    this.baseUrl,
    this.pauseWhileBackgrounded = true,
  });

  /// The connection mode to use.
  ///
  /// With [ConnectionMode.streaming] the connection stays open and receives
  /// updates whenever config state changes in the ConfigDirector dashboard.
  /// With [ConnectionMode.polling] config state is fetched during
  /// initialization and re-fetched every [pollingInterval].
  /// With [ConnectionMode.oneTime] config state is fetched during
  /// initialization and on context updates only.
  final ConnectionMode mode;

  /// How often to re-fetch config state when [mode] is [ConnectionMode.polling].
  /// It has no effect in any other mode.
  final Duration pollingInterval;

  /// How long to wait for initialization and context updates.
  ///
  /// When streaming, the operation may still succeed after it times out, as
  /// long as no unrecoverable errors are encountered. In the other modes a
  /// timed-out operation is not retried.
  final Duration timeout;

  /// The base URL of the ConfigDirector SDK server. Set this only when routing
  /// through a proxy. Refer to the docs on how to configure a proxy for the
  /// client SDK.
  final Uri? baseUrl;

  /// Whether to pause the connection while the app is in the background and
  /// resume it when the app returns to the foreground.
  ///
  /// Mobile operating systems terminate background connections on their own, so
  /// this is enabled by default. Set it to `false` to manage the connection
  /// yourself with `pauseNetwork` and `resumeNetwork`.
  final bool pauseWhileBackgrounded;
}

/// Configuration for a `ConfigDirectorClient`.
@immutable
final class ConfigDirectorClientOptions {
  const ConfigDirectorClientOptions({
    this.metadata,
    this.connection = const ConnectionOptions(),
    this.logger,
  });

  /// Metadata about your application that stays constant for the lifetime of
  /// the connection.
  final ConfigDirectorMetaContext? metadata;

  /// Connection options.
  final ConnectionOptions connection;

  /// Where the SDK writes its logs. Defaults to a [ConsoleLogger] at the
  /// [ConfigDirectorLogLevel.warn] level.
  ///
  /// To see more, provide a logger with a different level:
  /// ```dart
  /// ConfigDirectorClientOptions(
  ///   logger: ConsoleLogger(level: ConfigDirectorLogLevel.debug),
  /// )
  /// ```
  final ConfigDirectorLogger? logger;
}
