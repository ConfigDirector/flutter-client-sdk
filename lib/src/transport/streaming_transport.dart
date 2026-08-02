import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../errors.dart';
import '../eventsource/eventsource.dart';
import '../logger.dart';
import '../types.dart';
import 'transport.dart';

/// A [Transport] that keeps a server-sent events connection open, receiving
/// config state as soon as it changes on the server.
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
  VoidCallback? _readyStateListener;

  @override
  Stream<ConfigSet> get configSets => _configSets.stream;

  @override
  Future<void> connect(ConfigDirectorContext context, Duration timeout) async {
    _releaseEventSource();

    // Completes when the stream is open, or with an error when the server
    // rejects the connection in a way that retrying cannot fix.
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

    void onReadyStateChanged() {
      if (eventSource.readyState == ReadyState.open && !connected.isCompleted) {
        _logger.debug('[StreamingTransport] Connected');
        connected.complete();
      }
    }

    _readyStateListener = onReadyStateChanged;
    eventSource.addListener(onReadyStateChanged);
    eventSource.connect();

    // Give up waiting once the timeout elapses; the connection keeps retrying
    // in the background unless it failed fatally.
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

    if (!connected.isCompleted) {
      connected.completeError(_fatalError(state.status, state.error));
    } else {
      _logger.error(
        '[StreamingTransport] ${_fatalError(state.status, state.error).message}',
      );
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

  ConfigDirectorConnectionError _fatalError(int? status, Object? error) {
    final errorLine = error == null ? '' : ' Error: $error.';
    return ConfigDirectorConnectionError(
      'Connection failed with status: ${status ?? 'unknown'}.$errorLine '
      'This is an unrecoverable error, will not attempt to reconnect.',
      status ?? 0,
    );
  }

  void _dispatchMessage(String data) {
    try {
      final json = jsonDecode(data);
      if (json is! Map<String, Object?>) {
        throw const FormatException('Expected a JSON object');
      }
      if (!_configSets.isClosed) {
        _configSets.add(ConfigSet.fromJson(json));
      }
    } on FormatException catch (error, stackTrace) {
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

    final listener = _readyStateListener;
    if (listener != null) {
      eventSource.removeListener(listener);
      _readyStateListener = null;
    }
    unawaited(_messagesSubscription?.cancel());
    unawaited(_errorsSubscription?.cancel());
    _messagesSubscription = null;
    _errorsSubscription = null;

    eventSource.dispose();
    _eventSource = null;
  }
}
