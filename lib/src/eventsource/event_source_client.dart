import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'errors.dart';
import 'event_source_parser.dart';
import 'types.dart';

// Identifies a single connection attempt so late-arriving results (headers
// or stream events that resolve after EventSourceClient.close was called)
// can be recognized and discarded.
class _ConnectionToken {
  bool aborted = false;
}

class EventSourceClient extends ChangeNotifier {
  final Uri url;
  final String method;
  final String? body;
  final bool followRedirects;
  final Map<String, String> _headers;
  final http.Client _client;
  final bool _ownsClient;
  final ShouldReconnect _shouldReconnect;
  final CalculateReconnectDelay _calculateReconnectDelay;

  String? _lastEventId;

  int _reconnectAttempt = 0;
  _ConnectionToken _token = _ConnectionToken();
  Timer? _reconnectTimer;
  ReadyState _readyState = ReadyState.closed;
  Duration _serverReconnectionTime = const Duration(seconds: 2);
  StreamSubscription<String>? _subscription;
  Completer<void>? _readCompleter;
  bool _disposed = false;

  final StreamController<EventSourceMessage> _messages =
      StreamController.broadcast();
  final StreamController<String> _comments = StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();

  EventSourceClient({
    required this.url,
    this.method = 'GET',
    Map<String, String>? headers,
    this.body,
    this.followRedirects = true,
    this._lastEventId,
    http.Client? client,
    this._shouldReconnect = _defaultShouldReconnect,
    this._calculateReconnectDelay = _defaultCalculateReconnectDelay,
  }) : _headers = {'Accept': 'text/event-stream', ...?headers},
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  static bool _defaultShouldReconnect(ReconnectionState state) => true;

  static Duration _defaultCalculateReconnectDelay(ReconnectionState state) =>
      state.serverReconnectionTime;

  ReadyState get readyState => _readyState;

  String? get lastEventId => _lastEventId;

  Stream<EventSourceMessage> get messages => _messages.stream;

  Stream<String> get comments => _comments.stream;

  Stream<Object> get errors => _errors.stream;

  void connect() {
    if (_readyState != ReadyState.closed) {
      return;
    }

    _reconnectAttempt = 0;
    unawaited(_initiateConnection());
  }

  void close() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setReadyState(ReadyState.closed);
    _token.aborted = true;
    _subscription?.cancel();
    _subscription = null;

    final completer = _readCompleter;
    _readCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;

    close();
    unawaited(_messages.close());
    unawaited(_comments.close());
    unawaited(_errors.close());
    if (_ownsClient) {
      _client.close();
    }

    super.dispose();
  }

  Future<void> _initiateConnection() async {
    final token = _ConnectionToken();
    _token = token;
    _setReadyState(ReadyState.connecting);

    final request = http.Request(method, url)
      ..headers.addAll(_buildRequestHeaders())
      ..followRedirects = followRedirects;
    final requestBody = body;
    if (requestBody != null) {
      request.body = requestBody;
    }

    try {
      final response = await _client.send(request);
      await _handleResponse(response, token);
    } catch (error) {
      if (token.aborted) {
        close();
        return;
      }

      _errors.add(error);
      _scheduleReconnect(token, error: error);
    }
  }

  Future<void> _handleResponse(
    http.StreamedResponse response,
    _ConnectionToken token,
  ) async {
    if (token.aborted) {
      unawaited(response.stream.drain());
      return;
    }

    final status = response.statusCode;

    if (status == 204) {
      unawaited(response.stream.drain());
      _disconnected();
      return;
    }

    if (status >= 400) {
      unawaited(response.stream.drain());
      _scheduleReconnect(token, status: status);
      return;
    }

    if (!followRedirects && status >= 300 && status < 400) {
      unawaited(response.stream.drain());
      final error = StateError(
        'Redirect response received while redirects are disabled (status $status)',
      );
      _errors.add(error);
      _scheduleReconnect(token, error: error);
      return;
    }

    _setReadyState(ReadyState.open);
    _reconnectAttempt = 0;

    final parser = EventSourceParser(
      onEvent: (event) {
        final id = event.id;
        if (id != null) {
          _lastEventId = id;
        }
        _messages.add(event);
      },
      onComment: _comments.add,
      onRetry: (retryDelay) => _serverReconnectionTime = retryDelay,
    );

    await _readResponseStream(response.stream, parser);

    _scheduleReconnect(
      token,
      status: status,
      error: const StreamClosedError('The server response stream was closed'),
    );
  }

  Future<void> _readResponseStream(
    http.ByteStream stream,
    EventSourceParser parser,
  ) async {
    final completer = Completer<void>();
    _readCompleter = completer;

    final subscription = const Utf8Decoder(allowMalformed: true)
        .bind(stream)
        .listen(
          parser.parse,
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          cancelOnError: true,
        );
    _subscription = subscription;

    try {
      await completer.future;
    } finally {
      _subscription = null;
      _readCompleter = null;
    }

    parser.finish();
  }

  void _disconnected() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setReadyState(ReadyState.closed);
  }

  Map<String, String> _buildRequestHeaders() {
    final result = <String, String>{..._headers};
    final id = _lastEventId;
    if (id != null) {
      result['Last-Event-ID'] = id;
    }
    return result;
  }

  void _scheduleReconnect(
    _ConnectionToken token, {
    int? status,
    Object? error,
  }) {
    if (token.aborted) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;

    final state = (
      attempt: _reconnectAttempt,
      serverReconnectionTime: _serverReconnectionTime,
      status: status,
      error: error,
    );

    if (!_shouldReconnect(state)) {
      _disconnected();
      return;
    }

    _setReadyState(ReadyState.connecting);
    var delay = _calculateReconnectDelay(state);

    if (delay < const Duration(milliseconds: 1) ||
        delay > const Duration(hours: 1)) {
      _errors.add(
        ValueOutOfRangeError(
          'The calculated reconnect delay is out of range: $delay. Defaulting to $_serverReconnectionTime',
        ),
      );
      delay = _serverReconnectionTime;
    }

    _reconnectTimer = Timer(delay, () => unawaited(_initiateConnection()));
  }

  void _setReadyState(ReadyState state) {
    if (_readyState == state) {
      return;
    }
    _readyState = state;
    if (!_disposed) {
      notifyListeners();
    }
  }
}
