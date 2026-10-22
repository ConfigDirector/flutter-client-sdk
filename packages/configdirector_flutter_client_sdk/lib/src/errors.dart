/// Thrown when the connection to the ConfigDirector server fails.
final class ConfigDirectorConnectionException implements Exception {
  const ConfigDirectorConnectionException(this.message, [this.status]);

  /// A description of what went wrong.
  final String message;

  /// The HTTP status code the connection failed with, when one was received.
  final int? status;

  @override
  String toString() => 'ConfigDirectorConnectionException: $message';
}

/// Thrown when the client is given invalid arguments or options.
final class ConfigDirectorValidationException implements Exception {
  const ConfigDirectorValidationException(this.message);

  /// A description of which argument or option was invalid, and why.
  final String message;

  @override
  String toString() => 'ConfigDirectorValidationException: $message';
}

/// Thrown by `initialize` when the client cannot start from the values given
/// for offline mode, because one of them is refused or because they were
/// given in a mode other than `ConnectionMode.offline`.
final class ConfigDirectorInitializationException implements Exception {
  const ConfigDirectorInitializationException(this.message);

  /// A description of why the client could not start.
  final String message;

  @override
  String toString() => 'ConfigDirectorInitializationException: $message';
}
