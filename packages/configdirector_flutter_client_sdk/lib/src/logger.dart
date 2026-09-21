import 'package:flutter/foundation.dart';

/// The verbosity of a [ConfigDirectorLogger].
enum ConfigDirectorLogLevel {
  /// Drops every message.
  off(-1, 'OFF'),

  /// Failures the SDK could not recover from.
  error(0, 'ERROR'),

  /// Recoverable problems, such as a connection that is being retried. This is
  /// the default level.
  warn(1, 'WARN'),

  /// Lifecycle milestones, such as the client becoming ready.
  info(2, 'INFO'),

  /// Per-request and per-evaluation detail. Useful when diagnosing a problem,
  /// but noisy in production.
  debug(3, 'DEBUG');

  const ConfigDirectorLogLevel(this.severity, this.label);

  /// Higher values are more verbose. A logger emits a message when the
  /// message's severity is at most the logger's configured severity.
  final int severity;

  /// The label used when a level is written to the console.
  final String label;
}

/// The logging sink used by the SDK. Implement this to route SDK logs into your
/// application's own logging infrastructure.
abstract interface class ConfigDirectorLogger {
  /// Writes [message] at [ConfigDirectorLogLevel.debug], along with [error] and
  /// [stackTrace] when they are given.
  void debug(String message, [Object? error, StackTrace? stackTrace]);

  /// Writes [message] at [ConfigDirectorLogLevel.info], along with [error] and
  /// [stackTrace] when they are given.
  void info(String message, [Object? error, StackTrace? stackTrace]);

  /// Writes [message] at [ConfigDirectorLogLevel.warn], along with [error] and
  /// [stackTrace] when they are given.
  void warn(String message, [Object? error, StackTrace? stackTrace]);

  /// Writes [message] at [ConfigDirectorLogLevel.error], along with [error] and
  /// [stackTrace] when they are given.
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Decorates a message before it is written, typically to prefix it.
typedef LogMessageDecorator = String Function(String message);

/// The default logger, which writes to the console via [debugPrint].
///
/// Each record is written as a single line, with the error and stack trace (if
/// any) on the lines that follow:
///
/// ```text
/// 2026-08-02T09:41:07.412 [WARN] [ConfigDirector:flutter-client-sdk] message
/// ```
///
/// Timestamps are in local time.
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
      _log(ConfigDirectorLogLevel.debug, message, error, stackTrace);

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.info, message, error, stackTrace);

  @override
  void warn(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.warn, message, error, stackTrace);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(ConfigDirectorLogLevel.error, message, error, stackTrace);

  void _log(
    ConfigDirectorLogLevel messageLevel,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (messageLevel.severity > level.severity) {
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer(
      '$timestamp [${messageLevel.label}] ${_decorate(message)}',
    );
    if (error != null) {
      buffer.write('\n$error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }

    debugPrint(buffer.toString());
  }
}
