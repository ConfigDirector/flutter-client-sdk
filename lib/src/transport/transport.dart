import 'package:http/http.dart' as http;

import '../logger.dart';
import '../types.dart';

/// Calculates how long to wait before the reconnection attempt numbered
/// [attempt] (1-based).
typedef ConnectionRetryDelay = Duration Function(int attempt);

/// Everything a [Transport] needs to reach the ConfigDirector server.
final class TransportOptions {
  TransportOptions({
    required this.clientSdkKey,
    required this.baseUrl,
    required this.metaContext,
    required this.instanceId,
    required this.logger,
    required this.connectionRetryDelay,
    this.httpClient,
    this.pollingInterval,
  });

  final String clientSdkKey;
  final Uri baseUrl;

  /// Identifies the SDK and the host application. The client replaces it once
  /// the app name and version have been resolved from the platform, which
  /// happens before the first [Transport.connect].
  SdkMetaContext metaContext;

  final String instanceId;
  final ConfigDirectorLogger logger;
  final ConnectionRetryDelay connectionRetryDelay;

  /// An HTTP client to send requests with. When omitted, the transport creates
  /// and owns its own.
  final http.Client? httpClient;

  final Duration? pollingInterval;

  /// Builds the request payload shared by every transport.
  Map<String, Object?> buildPayload(
    ConfigDirectorContext context, {
    String? lastUpdateTimestamp,
  }) => {
    'givenContext': context.toJson(),
    'metaContext': metaContext.toJson(),
    'clientSdkKey': clientSdkKey,
    'instanceId': instanceId,
    if (lastUpdateTimestamp != null) 'lastUpdateTimestamp': lastUpdateTimestamp,
  };
}

/// Retrieves config state from the ConfigDirector server and publishes it on
/// [configSets].
abstract interface class Transport {
  /// Emits every config set received from the server.
  Stream<ConfigSet> get configSets;

  /// Connects using [context], returning once the connection is established, or
  /// once [timeout] elapses.
  ///
  /// Completing does not imply config state was received; that arrives on
  /// [configSets]. Never throws: failures are logged, and an unrecoverable one
  /// stops the transport from retrying.
  Future<void> connect(ConfigDirectorContext context, Duration timeout);

  /// Closes the connection without releasing the transport. It can be
  /// reconnected by calling [connect] again.
  void close();

  /// Closes the connection and releases every resource held by the transport.
  void dispose();
}

/// Statuses in the 4xx range mean the request itself is wrong (an invalid SDK
/// key, for instance), so retrying it would fail the same way.
bool isStatusFatal(int? status) =>
    status != null && status >= 400 && status < 500;
