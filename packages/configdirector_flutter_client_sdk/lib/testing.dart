/// Testing tools for the ConfigDirector Flutter SDK.
///
/// [createTestClient] builds a **test client**: the SDK's real
/// [ConfigDirectorClient] connected to an in-memory server that the test
/// controls. Only the connection to ConfigDirector, the telemetry, and the
/// app lifecycle and platform lookups are replaced; value parsing, readiness,
/// events, and `watch` streams are the production code. No network connection
/// is opened, no telemetry is sent, and no platform channel is used, so the
/// test client works under `flutter test` on the VM and in a browser alike.
///
/// ```dart
/// import 'package:configdirector_flutter_client_sdk/testing.dart';
///
/// final testClient = createTestClient(values: {'new-checkout': true});
/// await testClient.client.initialize();
///
/// expect(testClient.client.getValue('new-checkout', false), isTrue);
///
/// testClient.setValue('new-checkout', false);
/// await pumpEventQueue();
/// expect(testClient.client.getValue('new-checkout', true), isFalse);
/// ```
library;

import 'src/client/config_director_client.dart';
import 'src/logger.dart';
import 'src/testing/in_memory_connection.dart';
import 'src/types.dart';

/// Creates a [TestClient] holding a real [ConfigDirectorClient] that serves
/// [values] without a network connection.
///
/// [values] are the configs the client serves once initialized, keyed by config
/// key. The config type follows from each value's type: a `bool` is a boolean
/// config, an `int` an integer config, a `double` a float config, a `String` a
/// string config, and a `Map` with `String` keys or a `List` a JSON config.
/// A `null` value, a non-finite number, a blank key, or a value of any other
/// type throws a `ConfigDirectorValidationException`.
///
/// [timeout] is the client's connection timeout, which bounds how long a held
/// `initialize` or `updateContext` waits. It defaults to the SDK's production
/// timeout. [logger] is the logger the client uses, defaulting to the SDK's
/// console logger.
///
/// The client starts uninitialized, like a production client, so the code under
/// test can own the call to `initialize`. With nothing held or failed,
/// `initialize` completes at once with the client ready.
TestClient createTestClient({
  Map<String, Object?> values = const {},
  Duration? timeout,
  ConfigDirectorLogger? logger,
}) => TestClient._(
  InMemoryConnection(values: values, timeout: timeout, logger: logger),
);

/// A real [ConfigDirectorClient] together with the controls that decide what
/// its in-memory server delivers.
///
/// Create one with [createTestClient]. Value changes reach the client the way
/// a server update does, so `watch` streams, `onConfigsUpdated`, and reads all
/// reflect them. Deliveries arrive asynchronously: `await pumpEventQueue()` in
/// a `test`, or `await tester.pump()` in a `testWidgets`, before asserting.
final class TestClient {
  TestClient._(this._connection);

  final InMemoryConnection _connection;

  /// The SDK client under test. Pass it wherever production code accepts a
  /// [ConfigDirectorClient], and dispose it as production code would.
  ConfigDirectorClient get client => _connection.client;

  /// The context of every `initialize` and `updateContext` call, in call
  /// order. `initialize` without a context records an empty context.
  /// `resumeNetwork` is not recorded.
  List<ConfigDirectorContext> get contextUpdates => _connection.contextUpdates;

  /// Stores [value] under [key] and, once the client is connected, delivers an
  /// update carrying only [key]. See [createTestClient] for the accepted
  /// values.
  void setValue(String key, Object? value) => _connection.setValue(key, value);

  /// Removes the value under [key] and, once the client is connected, delivers
  /// a full update without it, so [key] reads as its in-code default value.
  void removeValue(String key) => _connection.removeValue(key);

  /// Replaces every stored value with [values], disarms any armed hold or
  /// failure, and, once the client is connected, delivers a full update. Use
  /// it to reset a test client shared across tests.
  void replaceValues(Map<String, Object?> values) =>
      _connection.replaceValues(values);

  /// Makes the next `initialize` wait, not ready, until
  /// [completeInitialization] or [failInitialization], or until the client's
  /// timeout elapses.
  void holdInitialization() => _connection.holdInitialization();

  /// Delivers the stored values to a held `initialize`, which then completes
  /// with the client ready. Called while a hold is armed but no `initialize`
  /// has picked it up, it disarms the hold.
  void completeInitialization() => _connection.completeInitialization();

  /// Fails a held `initialize` the way an invalid SDK key does: it completes
  /// promptly, the client is not ready, and an error is logged. Called while no
  /// `initialize` is held, it arms the next one to fail.
  void failInitialization() => _connection.failInitialization();

  /// Makes the next `updateContext` wait, not ready, until
  /// [completeContextUpdate] or [failContextUpdate], or until the client's
  /// timeout elapses.
  void holdContextUpdate() => _connection.holdContextUpdate();

  /// Delivers the stored values to a held `updateContext`, which then completes
  /// with the client ready. Called while a hold is armed but no `updateContext`
  /// has picked it up, it disarms the hold.
  void completeContextUpdate() => _connection.completeContextUpdate();

  /// Fails a held `updateContext` the way an invalid SDK key does: it completes
  /// promptly, the client is not ready, and an error is logged. Called while no
  /// `updateContext` is held, it arms the next one to fail.
  void failContextUpdate() => _connection.failContextUpdate();
}
