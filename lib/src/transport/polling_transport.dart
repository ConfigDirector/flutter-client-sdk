import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors.dart';
import '../logger.dart';
import '../types.dart';
import 'transport.dart';

/// A [Transport] that fetches config state on connect and then re-fetches it on
/// a fixed interval.
///
/// A polling interval of [Duration.zero] or less disables the interval, which is
/// how [OneTimeTransport] fetches config state only on connect.
///
/// [connect] never throws: a transient failure is logged and polling goes on,
/// and an unrecoverable one is logged and polling is not started.
class PollingTransport implements Transport {
  PollingTransport(TransportOptions options, {Duration? pollingInterval})
    : _options = options,
      _logger = options.logger,
      _url = options.baseUrl.resolve('client/polling/v1'),
      _pollingInterval =
          pollingInterval ??
          options.pollingInterval ??
          const Duration(seconds: 60),
      _httpClient = options.httpClient ?? http.Client(),
      _ownsHttpClient = options.httpClient == null;

  final TransportOptions _options;
  final ConfigDirectorLogger _logger;
  final Uri _url;
  final Duration _pollingInterval;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  final StreamController<ConfigSet> _configSets =
      StreamController<ConfigSet>.broadcast();

  Timer? _pollingTimer;
  String? _lastUpdateTimestamp;
  bool _hasFatalError = false;
  int _connectionGeneration = 0;

  @override
  Stream<ConfigSet> get configSets => _configSets.stream;

  @override
  Future<void> connect(ConfigDirectorContext context, Duration timeout) async {
    _cancelPolling();
    _connectionGeneration += 1;
    final generation = _connectionGeneration;

    try {
      await _fetchConfigs(context, timeout);
    } on ConfigDirectorConnectionException catch (error, stackTrace) {
      if (_hasFatalError) {
        _logger.error(
          '[PollingTransport] The initial fetch failed with an unrecoverable '
          'error, will not poll',
          error,
          stackTrace,
        );
      } else {
        _logger.warn(
          '[PollingTransport] The initial fetch failed, will keep polling',
          error,
          stackTrace,
        );
      }
    } finally {
      if (!_hasFatalError && generation == _connectionGeneration) {
        _schedulePolling(context, timeout);
      }
    }
  }

  void _schedulePolling(ConfigDirectorContext context, Duration timeout) {
    if (_pollingInterval <= Duration.zero) {
      return;
    }

    _pollingTimer = Timer.periodic(_pollingInterval, (_) async {
      try {
        await _fetchConfigs(context, timeout);
      } on Object catch (error, stackTrace) {
        _logger.warn(
          '[PollingTransport] Error during polling',
          error,
          stackTrace,
        );
      }
    });
  }

  Future<void> _fetchConfigs(
    ConfigDirectorContext context,
    Duration timeout,
  ) async {
    if (_hasFatalError) {
      _logger.warn(
        '[PollingTransport] There was a prior unrecoverable error. '
        'Ignoring attempt to reconnect.',
      );
      return;
    }

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            _url,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
              _options.buildPayload(
                context,
                lastUpdateTimestamp: _lastUpdateTimestamp,
              ),
            ),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw ConfigDirectorConnectionException(
        'Connection timed out after ${timeout.inMilliseconds}ms.',
      );
    } on Object catch (error) {
      throw ConfigDirectorConnectionException(
        'Connection failed with error: $error.',
      );
    }

    _throwOnErrorStatus(response);

    if (response.statusCode != 200) {
      return;
    }

    _dispatchConfigSet(response.body);
  }

  void _throwOnErrorStatus(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return;
    }

    if (isStatusFatal(status)) {
      _hasFatalError = true;
      close();
      final body = response.body.trim();
      throw ConfigDirectorConnectionException(
        'Connection failed with status: $status${body.isEmpty ? '' : ' ($body)'}. '
        'This is an unrecoverable error, retry attempts will be ignored.',
        status,
      );
    }

    throw ConfigDirectorConnectionException(
      'Connection failed with status: $status',
      status,
    );
  }

  void _dispatchConfigSet(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (error) {
      throw ConfigDirectorConnectionException(
        'Failed to parse the response from the server: $error',
      );
    }

    if (json is! Map<String, Object?>) {
      throw const ConfigDirectorConnectionException(
        'The server responded with an unexpected payload.',
      );
    }

    final ConfigSet configSet;
    try {
      configSet = ConfigSet.fromJson(json);
    } on Object catch (error) {
      throw ConfigDirectorConnectionException(
        'The server responded with an unexpected payload: $error',
      );
    }
    _lastUpdateTimestamp = configSet.timestamp;
    if (!_configSets.isClosed) {
      _configSets.add(configSet);
    }
  }

  @override
  void close() {
    _cancelPolling();
    _connectionGeneration += 1;
  }

  void _cancelPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void dispose() {
    close();
    unawaited(_configSets.close());
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}

/// A [Transport] that fetches config state on connect only, never polling for
/// updates afterwards.
final class OneTimeTransport extends PollingTransport {
  OneTimeTransport(super.options) : super(pollingInterval: Duration.zero);
}
