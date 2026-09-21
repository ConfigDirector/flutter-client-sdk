enum ReadyState { connecting, open, closed }

typedef ReconnectionState = ({
  int attempt,

  Duration serverReconnectionTime,

  int? status,

  Object? error,
});

final class EventSourceMessage {
  const EventSourceMessage({this.id, this.type, required this.data});

  final String? id;

  final String? type;

  final String data;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventSourceMessage &&
          other.id == id &&
          other.type == type &&
          other.data == data);

  @override
  int get hashCode => Object.hash(id, type, data);

  @override
  String toString() => 'EventSourceMessage(id: $id, type: $type, data: $data)';
}

typedef ShouldReconnect = bool Function(ReconnectionState state);

typedef CalculateReconnectDelay = Duration Function(ReconnectionState state);

typedef EventSourceMessageHandler = void Function(EventSourceMessage message);

typedef EventSourceCommentHandler = void Function(String comment);

typedef EventParserRetryCallback = void Function(Duration retryDelay);
