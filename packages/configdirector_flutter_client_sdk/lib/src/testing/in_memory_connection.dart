import 'dart:async';

import 'package:flutter/widgets.dart';

import '../client/client_events.dart';
import '../client/client_options.dart';
import '../client/config_director_client.dart';
import '../client/default_config_director_client.dart';
import '../lifecycle.dart';
import '../logger.dart';
import '../telemetry/telemetry_client.dart';
import '../telemetry/telemetry_events.dart';
import '../transport/transport.dart';
import '../types.dart';
import 'test_value_encoder.dart';

const String _placeholderSdkKey = 'test-client';
const String _environmentId = 'test-environment';
const String _projectId = 'test-project';
const ConfigDirectorMetaContext _fixedMetadata = ConfigDirectorMetaContext(
  appName: 'test-client',
  appVersion: '0.0.0',
);

final class InMemoryConnection {
  InMemoryConnection({
    Map<String, Object?> values = const {},
    Duration? timeout,
    ConfigDirectorLogger? logger,
  }) : _values = _encodeAll(values) {
    _client = DefaultConfigDirectorClient(
      _placeholderSdkKey,
      options: ConfigDirectorClientOptions(
        metadata: _fixedMetadata,
        connection: ConnectionOptions(
          timeout: timeout ?? const ConnectionOptions().timeout,
        ),
        logger: logger,
      ),
      transportFactory: (options) {
        _logger = options.logger;
        return _InMemoryTransport(this);
      },
      lifecycleWatcher: const _NoLifecycleWatcher(),
      appInfoResolver: () async => const ConfigDirectorMetaContext(),
      telemetryClient: const _NoTelemetryClient(),
    );
  }

  late final DefaultConfigDirectorClient _client;
  late final ConfigDirectorLogger _logger;

  final StreamController<ConfigSet> _configSets =
      StreamController<ConfigSet>.broadcast();
  final _AttemptControls _initialization = _AttemptControls();
  final _AttemptControls _contextUpdate = _AttemptControls();
  final List<ConfigDirectorContext> _contextUpdates = [];

  Map<String, ConfigState> _values;
  int _attemptGeneration = 0;
  bool _connected = false;

  ConfigDirectorClient get client => _client;

  List<ConfigDirectorContext> get contextUpdates =>
      List.unmodifiable(_contextUpdates);

  void setValue(String key, Object? value) {
    final configState = encodeTestValue(key, value);
    _values[key] = configState;
    _deliverIfConnected(_configSet(ConfigSetKind.delta, {key: configState}));
  }

  void removeValue(String key) {
    _values.remove(key);
    _deliverIfConnected(_fullUpdate());
  }

  void replaceValues(Map<String, Object?> values) {
    _values = _encodeAll(values);
    _initialization.disarm();
    _contextUpdate.disarm();
    _deliverIfConnected(_fullUpdate());
  }

  void holdInitialization() => _initialization.hold();

  void completeInitialization() => _initialization.complete();

  void failInitialization() => _initialization.fail();

  void holdContextUpdate() => _contextUpdate.hold();

  void completeContextUpdate() => _contextUpdate.complete();

  void failContextUpdate() => _contextUpdate.fail();

  Future<ConnectOutcome> _connect(
    ConfigDirectorContext context,
    Duration timeout,
    ClientConnectAction action,
  ) {
    _endAttempt();
    final controls = switch (action) {
      ClientConnectAction.initialization => _initialization,
      ClientConnectAction.contextUpdate => _contextUpdate,
      ClientConnectAction.networkResume => null,
    };
    if (controls == null) {
      return _finish(action, Future.value(_AttemptOutcome.completed));
    }

    _contextUpdates.add(context);
    return _finish(action, controls.begin(timeout));
  }

  Future<ConnectOutcome> _finish(
    ClientConnectAction action,
    Future<_AttemptOutcome> attempt,
  ) {
    final generation = _attemptGeneration;
    return attempt.then(
      (outcome) => switch (outcome) {
        _AttemptOutcome.completed => _scheduleFirstDelivery(generation),
        _AttemptOutcome.ended => ConnectOutcome.connected,
        _AttemptOutcome.failed => _failAttempt(action),
      },
    );
  }

  ConnectOutcome _scheduleFirstDelivery(int generation) {
    scheduleMicrotask(() {
      if (generation != _attemptGeneration) {
        return;
      }
      _connected = true;
      _deliver(_fullUpdate());
    });
    return ConnectOutcome.connected;
  }

  ConnectOutcome _failAttempt(ClientConnectAction action) {
    _logger.error(
      '[InMemoryConnection] Connection failed with status: 401. Error: the '
      'test client failed this ${action.description}. This is an '
      'unrecoverable error, will not attempt to reconnect.',
    );
    return ConnectOutcome.failedFatally;
  }

  void _endAttempt() {
    _attemptGeneration += 1;
    _connected = false;
    _initialization.end();
    _contextUpdate.end();
  }

  void _close() => _endAttempt();

  void _dispose() {
    _close();
    unawaited(_configSets.close());
  }

  void _deliverIfConnected(ConfigSet configSet) {
    if (_connected) {
      _deliver(configSet);
    }
  }

  void _deliver(ConfigSet configSet) {
    if (!_configSets.isClosed) {
      _configSets.add(configSet);
    }
  }

  ConfigSet _fullUpdate() => _configSet(ConfigSetKind.full, _values);

  static ConfigSet _configSet(
    ConfigSetKind kind,
    Map<String, ConfigState> configs,
  ) => ConfigSet(
    environmentId: _environmentId,
    projectId: _projectId,
    configs: Map.unmodifiable(configs),
    kind: kind,
  );

  static Map<String, ConfigState> _encodeAll(Map<String, Object?> values) => {
    for (final entry in values.entries)
      entry.key: encodeTestValue(entry.key, entry.value),
  };
}

enum _Armed { nothing, hold, failure }

enum _AttemptOutcome { completed, ended, failed }

final class _AttemptControls {
  _Armed _armed = _Armed.nothing;
  _HeldAttempt? _held;

  void hold() => _armed = _Armed.hold;

  void disarm() => _armed = _Armed.nothing;

  void complete() {
    if (_held != null) {
      _settle(_AttemptOutcome.completed);
    } else if (_armed == _Armed.hold) {
      _armed = _Armed.nothing;
    }
  }

  void fail() {
    if (_held != null) {
      _settle(_AttemptOutcome.failed);
    } else {
      _armed = _Armed.failure;
    }
  }

  void end() => _settle(_AttemptOutcome.ended);

  Future<_AttemptOutcome> begin(Duration timeout) {
    final armed = _armed;
    _armed = _Armed.nothing;
    switch (armed) {
      case _Armed.nothing:
        return Future.value(_AttemptOutcome.completed);
      case _Armed.failure:
        return Future.value(_AttemptOutcome.failed);
      case _Armed.hold:
        final held = _HeldAttempt(timeout, _endIfStillHeld);
        _held = held;
        return held.outcome;
    }
  }

  void _endIfStillHeld(_HeldAttempt attempt) {
    if (_held == attempt) {
      end();
    }
  }

  void _settle(_AttemptOutcome outcome) {
    final held = _held;
    if (held == null) {
      return;
    }
    _held = null;
    held.settle(outcome);
  }
}

final class _HeldAttempt {
  _HeldAttempt(Duration timeout, void Function(_HeldAttempt) onTimeout) {
    _timer = Timer(timeout, () => onTimeout(this));
  }

  final Completer<_AttemptOutcome> _outcome = Completer<_AttemptOutcome>();
  late final Timer _timer;

  Future<_AttemptOutcome> get outcome => _outcome.future;

  void settle(_AttemptOutcome outcome) {
    _timer.cancel();
    _outcome.complete(outcome);
  }
}

final class _InMemoryTransport implements Transport {
  _InMemoryTransport(this._connection);

  final InMemoryConnection _connection;

  @override
  Stream<ConfigSet> get configSets => _connection._configSets.stream;

  @override
  Future<ConnectOutcome> connect(
    ConfigDirectorContext context,
    Duration timeout,
    ClientConnectAction action,
  ) => _connection._connect(context, timeout, action);

  @override
  void close() => _connection._close();

  @override
  void dispose() => _connection._dispose();
}

final class _NoLifecycleWatcher implements AppLifecycleWatcher {
  const _NoLifecycleWatcher();

  @override
  void start(void Function(AppLifecycleState state) onStateChanged) {}

  @override
  void stop() {}
}

final class _NoTelemetryClient implements TelemetryClient {
  const _NoTelemetryClient();

  @override
  void evaluatedConfig(EvaluatedConfigEvent event) {}

  @override
  Future<void> updateContext(ConfigDirectorContext? context) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
