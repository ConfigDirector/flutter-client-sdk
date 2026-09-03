final class StreamClosedException implements Exception {
  final String message;

  const StreamClosedException(this.message);

  @override
  String toString() => 'StreamClosedException: $message';
}

final class ValueOutOfRangeException implements Exception {
  final String message;

  const ValueOutOfRangeException(this.message);

  @override
  String toString() => 'ValueOutOfRangeException: $message';
}
