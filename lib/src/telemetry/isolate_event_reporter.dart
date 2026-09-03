import 'dart:async';
import 'dart:isolate';

import '../logger.dart';
import 'event_reporter.dart';

/// An [EventReporter] that prepares and sends every report from a background
/// isolate, so that hashing values, encoding the payload, and handling the
/// response never run on the isolate that is drawing frames.
///
/// This is the Dart counterpart of the web worker the browser SDKs use. Unlike
/// that worker, it is handed one message per flush rather than one per
/// evaluation: collecting events is cheap, so the queue stays on the main
/// isolate and only the expensive part of a flush crosses over.
///
/// The isolate is spawned on the first report that has something to send, and
/// lives until [close]. If it cannot be spawned, or if it exits unexpectedly,
/// reporting falls back to the current isolate rather than being lost.
final class IsolateEventReporter implements EventReporter {
  IsolateEventReporter({
    required String sdkKey,
    required Uri baseUrl,
    required TelemetryMetaContext metaContext,
    required ConfigDirectorLogger logger,
  }) : _sdkKey = sdkKey,
       _baseUrl = baseUrl,
       _metaContext = metaContext,
       _logger = logger;

  final String _sdkKey;
  final Uri _baseUrl;
  final TelemetryMetaContext _metaContext;
  final ConfigDirectorLogger _logger;

  final Map<int, Completer<ReporterResponse>> _pendingRequests = {};

  ReceivePort? _fromIsolate;
  Future<SendPort?>? _startup;
  EventReporter? _localReporter;
  int _nextRequestId = 0;
  bool _closed = false;

  @override
  Future<ReporterResponse> report(EventReportRequest request) async {
    if (_closed) {
      return const ReporterResponse.failed();
    }
    if (request.snapshot.isEmpty) {
      return const ReporterResponse.succeeded();
    }

    final port = await (_startup ??= _start());
    if (_closed) {
      return const ReporterResponse.failed();
    }
    if (port == null) {
      return _localFallback().report(request);
    }

    final id = _nextRequestId;
    _nextRequestId += 1;
    final completer = Completer<ReporterResponse>();
    _pendingRequests[id] = completer;
    try {
      port.send(_ReportMessage(id, request));
    } on Object catch (error, stackTrace) {
      _pendingRequests.remove(id);
      _logger.warn(
        '[IsolateEventReporter] Could not hand the telemetry batch to the '
        'telemetry isolate, dropping it',
        error,
        stackTrace,
      );
      return const ReporterResponse.failed();
    }

    return completer.future;
  }

  Future<SendPort?> _start() async {
    final fromIsolate = _fromIsolate = ReceivePort('configdirector-telemetry');
    final ready = Completer<SendPort?>();
    fromIsolate.listen((message) => _handleMessage(message, ready));

    try {
      await Isolate.spawn(
        _telemetryIsolateMain,
        _IsolateInit(
          responsePort: fromIsolate.sendPort,
          sdkKey: _sdkKey,
          metaContext: _metaContext,
          baseUrl: _baseUrl.toString(),
        ),
        onError: fromIsolate.sendPort,
        onExit: fromIsolate.sendPort,
        errorsAreFatal: true,
        debugName: 'configdirector-telemetry',
      );
    } on Object catch (error, stackTrace) {
      _logger.warn(
        '[IsolateEventReporter] Could not start the telemetry isolate, '
        'telemetry will be reported from the current isolate instead',
        error,
        stackTrace,
      );
      fromIsolate.close();
      _fromIsolate = null;
      return null;
    }

    return ready.future;
  }

  void _handleMessage(Object? message, Completer<SendPort?> ready) {
    switch (message) {
      case SendPort port:
        if (!ready.isCompleted) {
          ready.complete(port);
        }
      case _ReportResultMessage(:final id, :final response):
        _pendingRequests.remove(id)?.complete(response);
      case _LogMessage(:final level, :final message):
        _log(level, message);
      case final List<Object?> error:
        _logger.warn(
          '[IsolateEventReporter] The telemetry isolate failed: '
          '${error.join('\n')}',
        );
      case null:
        _handleIsolateExit(ready);
    }
  }

  void _handleIsolateExit(Completer<SendPort?> ready) {
    _fromIsolate?.close();
    _fromIsolate = null;

    final pending = _pendingRequests.values.toList(growable: false);
    _pendingRequests.clear();
    for (final request in pending) {
      request.complete(const ReporterResponse.failed());
    }

    if (!ready.isCompleted) {
      ready.complete(null);
    }
    if (_closed) {
      return;
    }

    _startup = Future.value(null);
    _logger.warn(
      '[IsolateEventReporter] The telemetry isolate stopped, telemetry will be '
      'reported from the current isolate instead',
    );
  }

  void _log(ConfigDirectorLogLevel level, String message) => switch (level) {
    ConfigDirectorLogLevel.debug => _logger.debug(message),
    ConfigDirectorLogLevel.info => _logger.info(message),
    ConfigDirectorLogLevel.warn => _logger.warn(message),
    ConfigDirectorLogLevel.error => _logger.error(message),
    ConfigDirectorLogLevel.off => null,
  };

  EventReporter _localFallback() => _localReporter ??= HttpEventReporter(
    sdkKey: _sdkKey,
    baseUrl: _baseUrl,
    metaContext: _metaContext,
    logger: _logger,
  );

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    await _localReporter?.close();

    final port = await (_startup ?? Future<SendPort?>.value());
    if (port == null) {
      _fromIsolate?.close();
      _fromIsolate = null;
      return;
    }

    port.send(const _CloseMessage());
  }
}

void _telemetryIsolateMain(_IsolateInit init) {
  final requests = ReceivePort();
  final reporter = HttpEventReporter(
    sdkKey: init.sdkKey,
    metaContext: init.metaContext,
    baseUrl: Uri.parse(init.baseUrl),
    logger: _IsolateLogger(init.responsePort),
  );

  var handled = Future<void>.value();
  requests.listen((message) {
    handled = handled.then((_) async {
      switch (message) {
        case _ReportMessage(:final id, :final request):
          final response = await reporter.report(request);
          init.responsePort.send(_ReportResultMessage(id, response));
        case _CloseMessage():
          await reporter.close();
          requests.close();
      }
    });
  });

  init.responsePort.send(requests.sendPort);
}

final class _IsolateLogger implements ConfigDirectorLogger {
  const _IsolateLogger(this._port);

  final SendPort _port;

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      _send(ConfigDirectorLogLevel.debug, message, error);

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      _send(ConfigDirectorLogLevel.info, message, error);

  @override
  void warn(String message, [Object? error, StackTrace? stackTrace]) =>
      _send(ConfigDirectorLogLevel.warn, message, error);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _send(ConfigDirectorLogLevel.error, message, error);

  void _send(ConfigDirectorLogLevel level, String message, Object? error) =>
      _port.send(
        _LogMessage(level, error == null ? message : '$message: $error'),
      );
}

final class _IsolateInit {
  const _IsolateInit({
    required this.responsePort,
    required this.sdkKey,
    required this.baseUrl,
    required this.metaContext,
  });

  final SendPort responsePort;
  final String sdkKey;
  final String baseUrl;
  final TelemetryMetaContext metaContext;
}

final class _ReportMessage {
  const _ReportMessage(this.id, this.request);

  final int id;
  final EventReportRequest request;
}

final class _ReportResultMessage {
  const _ReportResultMessage(this.id, this.response);

  final int id;
  final ReporterResponse response;
}

final class _LogMessage {
  const _LogMessage(this.level, this.message);

  final ConfigDirectorLogLevel level;
  final String message;
}

final class _CloseMessage {
  const _CloseMessage();
}
