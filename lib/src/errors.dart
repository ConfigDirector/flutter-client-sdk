/// Thrown when the connection to the ConfigDirector server fails.
final class ConfigDirectorConnectionError implements Exception {
  const ConfigDirectorConnectionError(this.message, [this.status]);

  /// A description of what went wrong.
  final String message;

  /// The HTTP status code the connection failed with, when one was received.
  final int? status;

  @override
  String toString() => 'ConfigDirectorConnectionError: $message';
}

/// Thrown when the client is given invalid arguments or options.
final class ConfigDirectorValidationError implements Exception {
  const ConfigDirectorValidationError(this.message);

  /// A description of which argument or option was invalid, and why.
  final String message;

  @override
  String toString() => 'ConfigDirectorValidationError: $message';
}
