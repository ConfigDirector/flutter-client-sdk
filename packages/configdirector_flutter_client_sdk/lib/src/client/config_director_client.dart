import '../errors.dart';
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
/// final client = ConfigDirectorClient(clientSdkKey: 'YOUR-SDK-KEY');
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
  ///
  /// [clientSdkKey] may be left out in [ConnectionMode.offline], which never
  /// connects:
  ///
  /// ```dart
  /// final client = ConfigDirectorClient(
  ///   options: const ConfigDirectorClientOptions(
  ///     connection: ConnectionOptions(
  ///       mode: ConnectionMode.offline,
  ///       values: {'new-checkout': true},
  ///     ),
  ///   ),
  /// );
  /// ```
  ///
  /// In every other mode, a missing or blank [clientSdkKey] throws a
  /// [ConfigDirectorValidationException].
  factory ConfigDirectorClient({
    String? clientSdkKey,
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
  /// In [ConnectionMode.offline] it opens no connection and completes once the
  /// values given in [ConnectionOptions.values] are loaded, with the client
  /// ready. It throws a [ConfigDirectorInitializationException] when they
  /// cannot be loaded, and the client is then not ready.
  ///
  /// [context] is the current user's context, used to evaluate targeting rules.
  /// A [context] whose [ConfigDirectorContext.kind] is invalid is ignored as a
  /// whole: the client logs an error and evaluates configs as if no context
  /// was given, so the `context` getter reads `null` afterwards.
  Future<void> initialize([ConfigDirectorContext? context]);

  /// Updates the user's context and re-evaluates every config against it.
  ///
  /// A [context] whose [ConfigDirectorContext.kind] is invalid is ignored as a
  /// whole: the client logs an error, stops using the previous context, and
  /// evaluates configs as if no context was given, so the `context` getter
  /// reads `null` afterwards.
  ///
  /// In [ConnectionMode.offline] the new context takes effect at once and no
  /// config value changes.
  Future<void> updateContext(ConfigDirectorContext context);

  /// The context the client is currently evaluating configs against, or `null`
  /// when there is none, as after a context with an invalid
  /// [ConfigDirectorContext.kind] was ignored.
  ///
  /// This does not change the moment [updateContext] is called: configs are
  /// evaluated against the previous context until the underlying connection
  /// succeeds or times out. In [ConnectionMode.offline] it changes at once.
  ConfigDirectorContext? get context;

  /// Whether the client is ready, meaning the connection to the server
  /// succeeded and config state was received. In [ConnectionMode.offline] it
  /// is ready once [initialize] has loaded the offline values.
  bool get isReady;

  /// Whether the client is trying to get its very first config state from the
  /// server.
  ///
  /// It is `false` on creation, becomes `true` when [initialize] is called on a
  /// client that has never received config state, stays `true` through timeouts
  /// and retries, and becomes `false` when the first config state arrives, when
  /// an unrecoverable connection error stops the retries, or on [dispose].
  /// [updateContext] and [resumeNetwork] never set it.
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

  /// Evaluates [configKey] the way [getValue] does, and says why it evaluated
  /// the way it did.
  ///
  /// The returned [ConfigEvaluation.value] is what [getValue] would have
  /// returned, so it is [defaultValue] whenever the config could not be served
  /// as `T`, and [ConfigEvaluation.reason] says why. Use this where the reason
  /// matters at the point of the read, such as when reporting an evaluation to
  /// another system; [getValue] is enough everywhere else. Like every read, it
  /// is emitted on [onConfigEvaluated] and counted in telemetry.
  ///
  /// ```dart
  /// final evaluation = client.evaluate('dark-mode', false);
  /// if (evaluation.reason == EvaluationReason.clientNotReady) { ... }
  /// ```
  ConfigEvaluation evaluate<T extends Object>(String configKey, T defaultValue);

  /// Watches [configKey] for changes, which can come from an update in the
  /// ConfigDirector dashboard or from a call to [updateContext].
  ///
  /// The returned stream emits the config's current value on subscription and
  /// then every time the evaluated value changes. Consecutive identical values
  /// are not re-emitted. When a full update no longer carries [configKey], the
  /// stream emits [defaultValue], as [getValue] would now return it. Cancel the
  /// subscription to stop watching.
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

  /// Emitted whenever config state is received from the server, with the keys
  /// the update carried and the keys a full update removed.
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
  /// [resumeNetwork] to re-establish the connection. It does nothing in
  /// [ConnectionMode.offline].
  void pauseNetwork();

  /// Resumes a connection paused by [pauseNetwork], reusing the last context
  /// given to [initialize] or [updateContext], or no context when that one was
  /// ignored for an invalid [ConfigDirectorContext.kind]. It does nothing in
  /// [ConnectionMode.offline].
  Future<void> resumeNetwork();

  /// Disposes of the client: closes the connection, every watch stream, and
  /// every event stream, and reports whatever telemetry is left.
  ///
  /// Call this when your application shuts down. The client cannot be used
  /// afterwards.
  void dispose();
}
