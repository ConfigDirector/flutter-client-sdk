final class StreamClosedException implements Exception {
  const StreamClosedException(this.message);

  final String message;

  @override
  String toString() => 'StreamClosedException: $message';
}

final class ValueOutOfRangeException implements Exception {
  const ValueOutOfRangeException(this.message);

  final String message;

  @override
  String toString() => 'ValueOutOfRangeException: $message';
}
