import '../constants.dart' as constants;
import '../errors.dart';
import '../logger.dart';
import '../native_value_encoder.dart';
import '../types.dart';
import 'client_options.dart';

enum LiveConnectionMode { streaming, polling }

sealed class ConnectionPlan {
  const ConnectionPlan();
}

final class Connect extends ConnectionPlan {
  const Connect({
    required this.mode,
    required this.clientSdkKey,
    required this.baseUrl,
    required this.timeout,
    required this.pollingInterval,
  });

  final LiveConnectionMode mode;
  final String clientSdkKey;
  final Uri baseUrl;
  final Duration timeout;
  final Duration pollingInterval;
}

final class StayOffline extends ConnectionPlan {
  const StayOffline(this.source);

  final OfflineSource source;
}

sealed class OfflineSource {
  const OfflineSource();
}

final class InCodeDefaultValues extends OfflineSource {
  const InCodeDefaultValues();
}

final class OfflineValues extends OfflineSource {
  const OfflineValues(this.configs);

  final Map<String, ConfigState> configs;
}

final class RejectedSource extends OfflineSource {
  const RejectedSource(this.message);

  final String message;
}

ConnectionPlan planConnection(
  String? clientSdkKey,
  ConnectionOptions connection,
  ConfigDirectorLogger logger,
) => switch (connection.mode) {
  ConnectionMode.offline => StayOffline(_offlineSourceOf(connection.values)),
  ConnectionMode.streaming => _planLiveConnection(
    LiveConnectionMode.streaming,
    clientSdkKey,
    connection,
    logger,
  ),
  ConnectionMode.polling => _planLiveConnection(
    LiveConnectionMode.polling,
    clientSdkKey,
    connection,
    logger,
  ),
};

ConnectionPlan _planLiveConnection(
  LiveConnectionMode mode,
  String? clientSdkKey,
  ConnectionOptions connection,
  ConfigDirectorLogger logger,
) {
  final validatedClientSdkKey = _validatedClientSdkKey(clientSdkKey);
  if (connection.values != null) {
    return StayOffline(
      RejectedSource(
        "The connection option 'values' applies only when the connection "
        "mode is offline, but the mode is ${mode.name}.",
      ),
    );
  }
  _validateTimeout(connection.timeout);
  return Connect(
    mode: mode,
    clientSdkKey: validatedClientSdkKey,
    baseUrl: _baseUrlOf(connection.baseUrl),
    timeout: connection.timeout,
    pollingInterval: _pollingIntervalFor(
      mode,
      connection.pollingInterval,
      logger,
    ),
  );
}

OfflineSource _offlineSourceOf(Map<String, Object?>? values) =>
    switch (values) {
      null => const InCodeDefaultValues(),
      final values => _encodedOfflineValues(values),
    };

OfflineSource _encodedOfflineValues(Map<String, Object?> values) {
  try {
    return OfflineValues(Map.unmodifiable(encodeNativeValues(values)));
  } on ConfigDirectorValidationException catch (error) {
    return RejectedSource(
      'The offline values could not be loaded. ${error.message}',
    );
  }
}

String _validatedClientSdkKey(String? clientSdkKey) {
  if (clientSdkKey == null || clientSdkKey.trim().isEmpty) {
    throw const ConfigDirectorValidationException(
      'No client SDK key was provided, the client cannot be instantiated '
      'without a valid client SDK key',
    );
  }
  return clientSdkKey;
}

void _validateTimeout(Duration timeout) {
  if (timeout <= Duration.zero) {
    throw ConfigDirectorValidationException(
      "Invalid timeout '$timeout'. The timeout must be positive.",
    );
  }
}

Uri _baseUrlOf(Uri? baseUrl) {
  if (baseUrl == null) {
    return constants.clientBaseUrl;
  }

  if (!baseUrl.isAbsolute) {
    throw ConfigDirectorValidationException(
      "Invalid base URL '$baseUrl'. The base URL must be absolute.",
    );
  }

  return baseUrl;
}

Duration _pollingIntervalFor(
  LiveConnectionMode mode,
  Duration configuredInterval,
  ConfigDirectorLogger logger,
) => switch (mode) {
  LiveConnectionMode.streaming => configuredInterval,
  LiveConnectionMode.polling => _raisedToTheMinimumPollingInterval(
    configuredInterval,
    logger,
  ),
};

Duration _raisedToTheMinimumPollingInterval(
  Duration configuredInterval,
  ConfigDirectorLogger logger,
) {
  const minimumInterval = constants.minimumPollingInterval;
  if (configuredInterval >= minimumInterval) {
    return configuredInterval;
  }

  logger.warn(
    '[ConfigDirectorClient] pollingInterval of ${configuredInterval.inSeconds} '
    'seconds is below the minimum of ${minimumInterval.inSeconds} seconds. '
    'Using ${minimumInterval.inSeconds} seconds.',
  );
  return minimumInterval;
}
