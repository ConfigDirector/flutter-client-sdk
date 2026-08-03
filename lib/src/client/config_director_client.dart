import '../types.dart';
import 'client_events.dart';
import 'client_options.dart';
import 'default_config_director_client.dart';

/// The ConfigDirector SDK client.
///
/// Applications should create a single instance and call [initialize] during
/// application startup.
///
/// ```dart
/// final client = ConfigDirectorClient('YOUR-SDK-KEY');
/// await client.initialize(const ConfigDirectorContext(id: 'user-123'));
/// final darkMode = client.getValue('dark-mode', false);
/// ```
///
/// After initialization, call [updateContext] to re-evaluate configs against a
/// new context, and [dispose] when the client is no longer needed.
abstract interface class ConfigDirectorClient {
  /// Creates a client for [clientSdkKey], the client SDK key from the
  /// ConfigDirector dashboard.
  ///
  /// The client is not ready to serve config values until [initialize]
  /// completes. Until then, every config evaluates to its default value.
  factory ConfigDirectorClient({
    required String clientSdkKey,
    ConfigDirectorClientOptions? options,
  }) {
    return DefaultConfigDirectorClient(clientSdkKey, options: options);
  }

  /// Connects to ConfigDirector to retrieve config evaluations. Until
  /// initialization succeeds, every config returns the default value passed to
  /// [watch] or [getValue].
  ///
  /// If the connection fails or is interrupted by a transient error (a network
  /// error, an internal server error, and so on) the client keeps trying to
  /// connect. If it fails with a persistent error, such as an invalid SDK key,
  /// the client stops trying and logs an error.
  ///
  /// [context] is the current user's context, used to evaluate targeting rules.
  Future<void> initialize([ConfigDirectorContext? context]);

  /// Updates the user's context and re-evaluates every config against it.
  Future<void> updateContext(ConfigDirectorContext context);

  /// The context the client is currently evaluating configs against, or `null`
  /// when there is none.
  ///
  /// This does not change the moment [updateContext] is called: configs are
  /// evaluated against the previous context until the underlying connection
  /// succeeds or times out.
  ConfigDirectorContext? get context;

  /// Whether the client is ready, meaning the connection to the server
  /// succeeded and config state was received.
  bool get isReady;

  /// Whether the client is currently initializing. It is `false` on creation,
  /// `true` after [initialize] is called, and `false` again once initialization
  /// completes.
  bool get isInitializing;

  /// Evaluates [configKey] against the current context and targeting rules.
  ///
  /// Returns [defaultValue] when config state is unavailable — for instance
  /// when called before initialization completes, or when the server value
  /// cannot be represented as `T`.
  ///
  /// `T` is inferred from [defaultValue] and may be [String], [bool], [int],
  /// [double], [num], or, for JSON configs, any type the decoded document is
  /// assignable to (usually `Map<String, dynamic>` or `List<dynamic>`).
  T getValue<T extends Object>(String configKey, T defaultValue);

  /// Watches [configKey] for changes, which can come from an update in the
  /// ConfigDirector dashboard or from a call to [updateContext].
  ///
  /// The returned stream emits the config's current value on subscription and
  /// then every time the evaluated value changes. Consecutive identical values
  /// are not re-emitted. Cancel the subscription to stop watching.
  ///
  /// ```dart
  /// StreamBuilder<bool>(
  ///   stream: client.watch('dark-mode', false),
  ///   builder: (context, snapshot) => MyApp(dark: snapshot.data ?? false),
  /// )
  /// ```
  Stream<T> watch<T extends Object>(String configKey, T defaultValue);

  /// Closes every stream currently watching [configKey].
  void unwatch(String configKey);

  /// Closes every stream returned by [watch].
  void unwatchAll();

  /// Emitted when the client becomes ready after connecting.
  Stream<ClientReadyEvent> get onClientReady;

  /// Emitted whenever config state is received from the server.
  Stream<ConfigsUpdatedEvent> get onConfigsUpdated;

  /// Emitted once a new context has taken effect.
  Stream<ContextUpdatedEvent> get onContextUpdated;

  /// Emitted every time a config is evaluated, by [getValue] or by a [watch]
  /// stream.
  Stream<ConfigEvaluatedEvent> get onConfigEvaluated;

  /// Pauses the network connection without discarding config state, event
  /// listeners, or watch streams.
  ///
  /// The client does this on its own while the app is backgrounded, unless
  /// [ConnectionOptions.pauseWhileBackgrounded] is disabled. Call
  /// [resumeNetwork] to re-establish the connection.
  void pauseNetwork();

  /// Resumes a connection paused by [pauseNetwork], reusing the last context
  /// given to [initialize] or [updateContext].
  Future<void> resumeNetwork();

  /// Disposes of the client: closes the connection, every watch stream, and
  /// every event stream, and reports whatever telemetry is left.
  ///
  /// Call this when your application shuts down. The client cannot be used
  /// afterwards.
  void dispose();
}
