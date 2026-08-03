import 'package:flutter/foundation.dart';

import '../types.dart';

/// What prompted the client to (re)connect.
enum ClientConnectAction {
  /// The client connected for the first time, from `initialize`.
  initialization('initialization'),

  /// The client reconnected to re-evaluate configs against a new context.
  contextUpdate('context update'),

  /// The client reconnected after the network was resumed, either by
  /// `resumeNetwork` or by the app returning to the foreground.
  networkResume('network resume');

  const ClientConnectAction(this.description);

  /// A human-readable name for the action, used when it is logged.
  final String description;
}

/// Emitted when the client becomes ready after connecting.
@immutable
final class ClientReadyEvent {
  const ClientReadyEvent(this.action);

  /// The operation that brought the client to a ready state.
  final ClientConnectAction action;

  @override
  String toString() => 'ClientReadyEvent(action: ${action.description})';
}

/// Emitted when config state is received from the server.
@immutable
final class ConfigsUpdatedEvent {
  const ConfigsUpdatedEvent(this.keys);

  /// The keys of the configs contained in the update. On a delta update, these
  /// are only the configs that changed.
  final List<String> keys;

  @override
  String toString() => 'ConfigsUpdatedEvent(keys: $keys)';
}

/// Emitted once a new context has taken effect.
@immutable
final class ContextUpdatedEvent {
  const ContextUpdatedEvent(this.context);

  /// The context configs are now evaluated against, or `null` once the context
  /// has been cleared.
  final ConfigDirectorContext? context;

  @override
  String toString() => 'ContextUpdatedEvent(context: $context)';
}

/// Emitted every time a config is evaluated.
@immutable
final class ConfigEvaluatedEvent {
  const ConfigEvaluatedEvent(this.evaluation);

  /// The value the config evaluated to, and why.
  final ConfigEvaluation evaluation;

  @override
  String toString() => 'ConfigEvaluatedEvent(evaluation: $evaluation)';
}
