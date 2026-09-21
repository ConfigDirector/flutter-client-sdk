import 'package:flutter/widgets.dart';

import 'logger.dart';

/// Reports app lifecycle transitions so the client can release its network
/// connection while the app is backgrounded.
abstract interface class AppLifecycleWatcher {
  /// Starts reporting transitions to [onStateChanged].
  void start(void Function(AppLifecycleState state) onStateChanged);

  /// Stops reporting transitions.
  void stop();
}

/// The default [AppLifecycleWatcher], backed by an [AppLifecycleListener].
final class WidgetsBindingLifecycleWatcher implements AppLifecycleWatcher {
  WidgetsBindingLifecycleWatcher(this._logger);

  final ConfigDirectorLogger _logger;

  AppLifecycleListener? _listener;

  @override
  void start(void Function(AppLifecycleState state) onStateChanged) {
    try {
      _listener = AppLifecycleListener(onStateChange: onStateChanged);
    } on Object catch (error) {
      _logger.warn(
        '[ConfigDirectorClient] The widgets binding is not initialized, so the '
        'SDK cannot follow the app lifecycle: the connection will not be paused '
        'automatically while the app is in the background, and telemetry will '
        'only be reported on its regular interval. Call '
        'WidgetsFlutterBinding.ensureInitialized() before creating the client, '
        'or pause and resume the connection manually.',
        error,
      );
    }
  }

  @override
  void stop() {
    _listener?.dispose();
    _listener = null;
  }
}
