final class StreamClosedError implements Exception {
  final String message;

  const StreamClosedError(this.message);

  @override
  String toString() => 'StreamClosedError: $message';
}

final class ValueOutOfRangeError implements Exception {
  final String message;

  const ValueOutOfRangeError(this.message);

  @override
  String toString() => 'ValueOutOfRangeError: $message';
}
