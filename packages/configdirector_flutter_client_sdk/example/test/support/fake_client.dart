import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';

/// A [ConfigDirectorClient] serving canned values, so widget tests never touch
/// the network.
///
/// Only the members the sample app uses are implemented; anything else throws
/// through [noSuchMethod].
class FakeConfigDirectorClient implements ConfigDirectorClient {
  FakeConfigDirectorClient({this.values = const {}, this.context});

  /// The evaluated value of each config key. Absent keys evaluate to the
  /// default value the caller passed.
  final Map<String, Object> values;

  @override
  final ConfigDirectorContext? context;

  @override
  bool get isReady => true;

  @override
  T getValue<T extends Object>(String configKey, T defaultValue) {
    final value = values[configKey];
    return value is T ? value : defaultValue;
  }

  @override
  Stream<T> watch<T extends Object>(String configKey, T defaultValue) =>
      Stream.value(getValue(configKey, defaultValue));

  @override
  Stream<ClientReadyEvent> get onClientReady => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
