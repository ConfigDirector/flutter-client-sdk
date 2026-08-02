import 'package:flutter/foundation.dart';

import '../types.dart';

/// What prompted the client to (re)connect.
enum ClientConnectAction {
  initialization('initialization'),
  contextUpdate('context update'),
  networkResume('network resume');

  const ClientConnectAction(this.description);

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

  final ConfigDirectorContext? context;

  @override
  String toString() => 'ContextUpdatedEvent(context: $context)';
}

/// Emitted every time a config is evaluated.
@immutable
final class ConfigEvaluatedEvent {
  const ConfigEvaluatedEvent(this.evaluation);

  final ConfigEvaluation evaluation;

  @override
  String toString() => 'ConfigEvaluatedEvent(evaluation: $evaluation)';
}
