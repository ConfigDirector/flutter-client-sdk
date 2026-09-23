import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';

class FakeConfigDirectorClient implements ConfigDirectorClient {
  FakeConfigDirectorClient({Map<String, Object>? values})
    : values = values ?? {};

  final Map<String, Object> values;
  final Set<String> keysWithoutValue = {};
  final List<ConfigDirectorContext?> initializeCalls = [];
  final List<ConfigDirectorContext> updateContextCalls = [];

  bool connectionSucceeds = true;
  Completer<void>? connectionGate;
  bool disposed = false;

  final StreamController<ClientReadyEvent> _clientReady =
      StreamController<ClientReadyEvent>.broadcast();
  final StreamController<ConfigsUpdatedEvent> _configsUpdated =
      StreamController<ConfigsUpdatedEvent>.broadcast();

  bool _ready = false;
  ConfigDirectorContext? _context;

  @override
  bool get isReady => _ready;

  @override
  ConfigDirectorContext? get context => _context;

  @override
  Stream<ClientReadyEvent> get onClientReady => _clientReady.stream;

  @override
  Stream<ConfigsUpdatedEvent> get onConfigsUpdated => _configsUpdated.stream;

  @override
  Future<void> initialize([ConfigDirectorContext? context]) {
    initializeCalls.add(context);
    return _connect(context, ClientConnectAction.initialization);
  }

  @override
  Future<void> updateContext(ConfigDirectorContext context) {
    updateContextCalls.add(context);
    return _connect(context, ClientConnectAction.contextUpdate);
  }

  @override
  T getValue<T extends Object>(String configKey, T defaultValue) =>
      evaluate(configKey, defaultValue).value as T;

  @override
  ConfigEvaluation evaluate<T extends Object>(
    String configKey,
    T defaultValue,
  ) {
    final value = values[configKey];
    final (
      Object result,
      String? valueId,
      EvaluationReason reason,
    ) = switch (value) {
      null when keysWithoutValue.contains(configKey) => (
        defaultValue,
        null,
        EvaluationReason.valueMissing,
      ),
      null => (
        defaultValue,
        null,
        _ready
            ? EvaluationReason.configStateMissing
            : EvaluationReason.clientNotReady,
      ),
      T() => (value, 'value-id-$configKey', EvaluationReason.foundMatch),
      _ => (defaultValue, null, EvaluationReason.typeMismatch),
    };
    return ConfigEvaluation(
      key: configKey,
      value: result,
      valueId: valueId,
      isDefaultValue: reason != EvaluationReason.foundMatch,
      reason: reason,
      context: _context,
    );
  }

  @override
  void dispose() {
    disposed = true;
    _ready = false;
    final gate = connectionGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    unawaited(_clientReady.close());
    unawaited(_configsUpdated.close());
  }

  void becomeReady(ClientConnectAction action) {
    _ready = true;
    _clientReady.add(ClientReadyEvent(action));
  }

  void receiveConfigs(List<String> keys) {
    _configsUpdated.add(ConfigsUpdatedEvent(keys));
  }

  Future<void> _connect(
    ConfigDirectorContext? context,
    ClientConnectAction action,
  ) async {
    _ready = false;
    await connectionGate?.future;
    if (disposed) {
      return;
    }
    _context = context;
    if (connectionSucceeds) {
      becomeReady(action);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
