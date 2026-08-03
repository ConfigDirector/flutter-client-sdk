import 'dart:async';

import 'package:configdirector_flutter_client_sdk/src/lifecycle.dart';
import 'package:configdirector_flutter_client_sdk/src/logger.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/event_reporter.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_client.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_events.dart';
import 'package:configdirector_flutter_client_sdk/src/transport/transport.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter/widgets.dart';

typedef ConnectCall = ({ConfigDirectorContext context, Duration timeout});

final class FakeTransport implements Transport {
  final StreamController<ConfigSet> _configSets =
      StreamController<ConfigSet>.broadcast();

  final List<ConnectCall> connectCalls = [];
  int closeCount = 0;
  bool disposed = false;

  /// Thrown by the next call to [connect], when set.
  Object? connectError;

  /// Delays [connect] before it completes, to exercise the connect timeout.
  Duration connectDelay = Duration.zero;

  @override
  Stream<ConfigSet> get configSets => _configSets.stream;

  @override
  Future<void> connect(ConfigDirectorContext context, Duration timeout) async {
    connectCalls.add((context: context, timeout: timeout));
    if (connectDelay > Duration.zero) {
      await Future<void>.delayed(connectDelay);
    }
    final error = connectError;
    if (error != null) {
      throw error;
    }
  }

  void emitConfigSet(ConfigSet configSet) => _configSets.add(configSet);

  @override
  void close() => closeCount++;

  @override
  void dispose() {
    disposed = true;
    unawaited(_configSets.close());
  }
}

final class FakeLifecycleWatcher implements AppLifecycleWatcher {
  void Function(AppLifecycleState state)? _onStateChanged;
  bool stopped = false;

  bool get isStarted => _onStateChanged != null;

  @override
  void start(void Function(AppLifecycleState state) onStateChanged) =>
      _onStateChanged = onStateChanged;

  @override
  void stop() {
    stopped = true;
    _onStateChanged = null;
  }

  void send(AppLifecycleState state) => _onStateChanged?.call(state);
}

final class FakeTelemetryClient implements TelemetryClient {
  final List<EvaluatedConfigEvent> events = [];
  final List<ConfigDirectorContext?> contextUpdates = [];
  int flushCount = 0;
  int closeCount = 0;

  @override
  void evaluatedConfig(EvaluatedConfigEvent event) => events.add(event);

  @override
  Future<void> updateContext(ConfigDirectorContext? context) async =>
      contextUpdates.add(context);

  @override
  Future<void> flush() async => flushCount++;

  @override
  Future<void> close() async => closeCount++;
}

final class FakeEventReporter implements EventReporter {
  final List<EventReportRequest> requests = [];
  int closeCount = 0;

  /// The response the next [report] completes with.
  ReporterResponse response = const ReporterResponse.succeeded();

  /// Thrown by [report] when set.
  Object? error;

  /// Held by [report] until completed, to exercise overlapping flushes.
  Completer<void>? gate;

  @override
  Future<ReporterResponse> report(EventReportRequest request) async {
    requests.add(request);
    await gate?.future;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return response;
  }

  @override
  Future<void> close() async => closeCount++;
}

/// A logger that records messages instead of writing them, keeping test output
/// clean while still allowing assertions on what was logged.
final class RecordingLogger implements ConfigDirectorLogger {
  final List<String> messages = [];

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      messages.add(message);

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      messages.add(message);

  @override
  void warn(String message, [Object? error, StackTrace? stackTrace]) =>
      messages.add(message);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      messages.add('$message${error == null ? '' : ': $error'}');
}

ConfigSet configSet({
  required Map<String, ConfigState> configs,
  ConfigSetKind kind = ConfigSetKind.full,
  String? timestamp,
}) => ConfigSet(
  environmentId: 'env-id',
  projectId: 'project-id',
  configs: configs,
  kind: kind,
  timestamp: timestamp,
);

ConfigState configState(
  String key,
  ConfigType type,
  String? value, {
  String valueId = 'value-id',
}) => ConfigState(
  id: '$key-id',
  key: key,
  type: type,
  value: value,
  valueId: valueId,
);
