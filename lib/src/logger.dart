import 'dart:developer' as developer;

/// The verbosity of a [ConfigDirectorLogger].
enum ConfigDirectorLogLevel {
  off(-1),
  error(0),
  warn(1),
  info(2),
  debug(3);

  const ConfigDirectorLogLevel(this.severity);

  /// Higher values are more verbose. A logger emits a message when the
  /// message's severity is at most the logger's configured severity.
  final int severity;
}

/// The logging sink used by the SDK. Implement this to route SDK logs into your
/// application's own logging infrastructure.
abstract interface class ConfigDirectorLogger {
  void debug(String message, [Object? error, StackTrace? stackTrace]);

  void info(String message, [Object? error, StackTrace? stackTrace]);

  void warn(String message, [Object? error, StackTrace? stackTrace]);

  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Decorates a message before it is written, typically to prefix it.
typedef LogMessageDecorator = String Function(String message);

/// The default logger, which writes to the developer log (visible in the
/// console and in Flutter DevTools).
final class ConsoleLogger implements ConfigDirectorLogger {
  ConsoleLogger({
    this.level = ConfigDirectorLogLevel.warn,
    LogMessageDecorator? messageDecorator,
  }) : _decorate = messageDecorator ?? _defaultDecorator;

  static String _defaultDecorator(String message) =>
      '[ConfigDirector:flutter-client-sdk] $message';

  /// Messages less severe than this level are dropped.
  final ConfigDirectorLogLevel level;

  final LogMessageDecorator _decorate;

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.debug, 500, message, error, stackTrace);

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.info, 800, message, error, stackTrace);

  @override
  void warn(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.warn, 900, message, error, stackTrace);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.error, 1000, message, error, stackTrace);

  void _log(
    ConfigDirectorLogLevel messageLevel,
    int developerLevel,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (messageLevel.severity > level.severity) {
      return;
    }

    developer.log(
      _decorate(message),
      name: 'ConfigDirector',
      level: developerLevel,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
