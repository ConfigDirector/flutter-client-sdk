import 'dart:async';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';

/// A [ConfigDirectorClient] that serves canned values and records the contexts
/// it is given, so widget tests never touch the network.
///
/// Only the members the sample app uses are implemented; anything else throws
/// through [noSuchMethod].
class FakeConfigDirectorClient implements ConfigDirectorClient {
  FakeConfigDirectorClient([this.values = const {}]);

  /// The evaluated value of each config key. Keys that are absent evaluate to
  /// the default value the caller passed.
  final Map<String, Object> values;

  /// Every context passed to [updateContext], in order.
  final List<ConfigDirectorContext> updatedContexts = [];

  final StreamController<ContextUpdatedEvent> _contextUpdated =
      StreamController<ContextUpdatedEvent>.broadcast();

  ConfigDirectorContext? _context;

  @override
  void dispose() {
    _contextUpdated.close();
  }

  @override
  bool get isReady => true;

  @override
  ConfigDirectorContext? get context => _context;

  @override
  T getValue<T extends Object>(String configKey, T defaultValue) {
    final value = values[configKey];
    return value is T ? value : defaultValue;
  }

  @override
  Stream<T> watch<T extends Object>(String configKey, T defaultValue) =>
      Stream.value(getValue(configKey, defaultValue));

  @override
  Future<void> updateContext(ConfigDirectorContext context) async {
    updatedContexts.add(context);
    _context = context;
    _contextUpdated.add(ContextUpdatedEvent(context));
  }

  @override
  Stream<ClientReadyEvent> get onClientReady => const Stream.empty();

  @override
  Stream<ContextUpdatedEvent> get onContextUpdated => _contextUpdated.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
