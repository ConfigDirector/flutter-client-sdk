import 'dart:async';
import 'dart:convert';

import '../eventsource/eventsource.dart';
import '../logger.dart';
import '../types.dart';
import 'transport.dart';

/// A [Transport] that keeps a server-sent events connection open, receiving
/// config state as soon as it changes on the server.
///
/// [connect] never throws: a transient failure is retried in the background,
/// and an unrecoverable one is logged and not retried.
final class StreamingTransport implements Transport {
  StreamingTransport(TransportOptions options)
    : _options = options,
      _logger = options.logger,
      _url = options.baseUrl.resolve('client/sse/v1');

  final TransportOptions _options;
  final ConfigDirectorLogger _logger;
  final Uri _url;

  final StreamController<ConfigSet> _configSets =
      StreamController<ConfigSet>.broadcast();

  EventSourceClient? _eventSource;
  StreamSubscription<EventSourceMessage>? _messagesSubscription;
  StreamSubscription<Object>? _errorsSubscription;
  StreamSubscription<ReadyState>? _readyStateSubscription;

  @override
  Stream<ConfigSet> get configSets => _configSets.stream;

  @override
  Future<void> connect(ConfigDirectorContext context, Duration timeout) async {
    _releaseEventSource();

    final connected = Completer<void>();

    final eventSource = EventSourceClient(
      url: _url,
      method: 'POST',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(_options.buildPayload(context)),
      client: _options.httpClient,
      shouldReconnect: (state) => _shouldReconnect(state, connected),
      calculateReconnectDelay: _calculateReconnectDelay,
    );
    _eventSource = eventSource;

    _messagesSubscription = eventSource.messages.listen(
      (message) => _dispatchMessage(message.data),
    );
    _errorsSubscription = eventSource.errors.listen(
      (error) => _logger.debug('[StreamingTransport] Error', error),
    );

    _readyStateSubscription = eventSource.readyStates.listen((state) {
      if (state == ReadyState.open && !connected.isCompleted) {
        _logger.debug('[StreamingTransport] Connected');
        connected.complete();
      }
    });
    eventSource.connect();

    final timeoutTimer = Timer(timeout, () {
      if (!connected.isCompleted) {
        connected.complete();
      }
    });

    try {
      await connected.future;
    } finally {
      timeoutTimer.cancel();
    }
  }

  bool _shouldReconnect(ReconnectionState state, Completer<void> connected) {
    if (!isStatusFatal(state.status)) {
      return true;
    }

    _logger.error(
      '[StreamingTransport] ${_fatalErrorMessage(state.status, state.error)}',
    );
    if (!connected.isCompleted) {
      connected.complete();
    }
    return false;
  }

  Duration _calculateReconnectDelay(ReconnectionState state) {
    final delay = _options.connectionRetryDelay(state.attempt);
    final message =
        '[StreamingTransport] Scheduling reconnect attempt #${state.attempt} '
        'in ${delay.inMilliseconds}ms.';
    if (state.attempt <= 5) {
      _logger.info(message);
    } else {
      _logger.warn(message);
    }
    return delay;
  }

  String _fatalErrorMessage(int? status, Object? error) {
    final errorLine = error == null ? '' : ' Error: $error.';
    return 'Connection failed with status: ${status ?? 'unknown'}.$errorLine '
        'This is an unrecoverable error, will not attempt to reconnect.';
  }

  void _dispatchMessage(String data) {
    try {
      final json = jsonDecode(data);
      if (json is! Map<String, Object?>) {
        throw const FormatException('Expected a JSON object');
      }
      final configSet = ConfigSet.fromJson(json);
      if (!_configSets.isClosed) {
        _configSets.add(configSet);
      }
    } on Object catch (error, stackTrace) {
      _logger.error(
        '[StreamingTransport] Error parsing and dispatching config data update',
        error,
        stackTrace,
      );
    }
  }

  @override
  void close() => _eventSource?.close();

  @override
  void dispose() {
    _releaseEventSource();
    unawaited(_configSets.close());
  }

  void _releaseEventSource() {
    final eventSource = _eventSource;
    if (eventSource == null) {
      return;
    }

    unawaited(_readyStateSubscription?.cancel());
    unawaited(_messagesSubscription?.cancel());
    unawaited(_errorsSubscription?.cancel());
    _readyStateSubscription = null;
    _messagesSubscription = null;
    _errorsSubscription = null;

    eventSource.dispose();
    _eventSource = null;
  }
}
