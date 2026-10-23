import 'package:flutter/foundation.dart';

import '../constants.dart' as constants;
import '../errors.dart';
import '../logger.dart';
import '../types.dart';

/// How the client connects to the ConfigDirector server.
@immutable
final class ConnectionOptions {
  const ConnectionOptions({
    this.mode = ConnectionMode.streaming,
    this.values,
    this.pollingInterval = constants.defaultPollingInterval,
    this.timeout = const Duration(seconds: 3),
    this.baseUrl,
    this.pauseWhileBackgrounded = true,
  });

  /// The connection mode to use.
  ///
  /// With [ConnectionMode.streaming] the connection stays open and receives
  /// updates whenever config state changes in the ConfigDirector dashboard.
  /// With [ConnectionMode.polling] config state is fetched during
  /// initialization and re-fetched every [pollingInterval], which defaults to
  /// 60 seconds and is never shorter than 30 seconds. With
  /// [ConnectionMode.offline] the client never connects and serves [values]
  /// instead.
  final ConnectionMode mode;

  /// The values to serve when [mode] is [ConnectionMode.offline], keyed by
  /// config key.
  ///
  /// The config type of each value follows from its type: a `bool` is a
  /// boolean config, an `int` an integer config, a `double` a float config, a
  /// `String` a string config, and a `Map` with `String` keys or a `List` a
  /// JSON config. Every context receives the same value. The values are read
  /// once, when the client is created. Leave them out to serve the in-code
  /// default value of every config.
  ///
  /// `initialize` throws a [ConfigDirectorInitializationException] when a
  /// value is `null`, a non-finite number, on the web an integer beyond
  /// 2^53 - 1 in either direction, or of any other type, when a key is blank,
  /// or when values are given in a mode other than [ConnectionMode.offline].
  final Map<String, Object?>? values;

  /// How often to re-fetch config state when [mode] is [ConnectionMode.polling].
  ///
  /// Defaults to 60 seconds. The minimum is 30 seconds. A value below the
  /// minimum is raised to the minimum and a warning is logged. It has no effect
  /// in the other modes.
  final Duration pollingInterval;

  /// How long to wait for initialization and context updates. Must be
  /// positive.
  ///
  /// The first initialization also reads the app name and version from the
  /// platform, which has its own budget of the same length before the
  /// connection is attempted.
  ///
  /// When streaming, the operation may still succeed after it times out, as
  /// long as no unrecoverable errors are encountered. When polling, a fetch
  /// that timed out is retried on the next polling interval. It has no effect
  /// in [ConnectionMode.offline].
  final Duration timeout;

  /// The base URL of the ConfigDirector SDK server. Set this only when routing
  /// through a proxy. Refer to the docs on how to configure a proxy for the
  /// client SDK. It has no effect in [ConnectionMode.offline].
  final Uri? baseUrl;

  /// Whether to pause the connection while the app is in the background and
  /// resume it when the app returns to the foreground.
  ///
  /// Mobile operating systems terminate background connections on their own, so
  /// this is enabled by default. Set it to `false` to manage the connection
  /// yourself with `pauseNetwork` and `resumeNetwork`. It has no effect in
  /// [ConnectionMode.offline], which has no connection to pause.
  final bool pauseWhileBackgrounded;
}

/// A store the client keeps its last received values in between launches.
///
/// The client writes one entry, a string whose format belongs to the SDK and
/// may change between SDK versions, and reads it back on the next launch. One
/// instance serves one client. See [CachingOptions].
abstract interface class CachingProvider {
  /// Returns the stored entry, or `null` when nothing is stored.
  Future<String?> read();

  /// Replaces the stored entry. The client never writes an entry larger than
  /// [sizeLimit].
  Future<void> write(String value);

  /// Removes the stored entry.
  Future<void> remove();

  /// The largest entry, in bytes, this store accepts.
  int sizeLimit();
}

/// Options for the values the client keeps on the device between launches.
///
/// By default, the last values received from ConfigDirector are kept on the
/// device and served on the next launch of the same context, with the
/// evaluation reason [EvaluationReason.cached], until live values arrive. The
/// client is not ready while it serves them. Ignored in
/// [ConnectionMode.offline].
@immutable
final class CachingOptions {
  const CachingOptions({this.enabled = true, this.provider});

  /// Whether to keep the last values received on the device. With `false`,
  /// nothing is read or written, even when a [provider] is given.
  final bool enabled;

  /// The store for the values. Defaults to `shared_preferences`, under a key
  /// derived from the client SDK key, with a size limit of 256 KB.
  final CachingProvider? provider;
}

/// Configuration for a `ConfigDirectorClient`.
@immutable
final class ConfigDirectorClientOptions {
  const ConfigDirectorClientOptions({
    this.metadata,
    this.connection = const ConnectionOptions(),
    this.caching = const CachingOptions(),
    this.logger,
  });

  /// Metadata about your application that stays constant for the lifetime of
  /// the connection.
  ///
  /// Whichever of the app name and version this does not carry is read from the
  /// platform — the application label and `versionName` on Android, the bundle
  /// display name and short version string on iOS and macOS, and `version.json`
  /// on web — so setting this is only needed to report something else.
  final ConfigDirectorMetaContext? metadata;

  /// Connection options.
  final ConnectionOptions connection;

  /// Options for the values kept on the device between launches. See
  /// [CachingOptions].
  final CachingOptions caching;

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
