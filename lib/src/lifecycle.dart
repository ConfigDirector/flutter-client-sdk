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

/// The default [AppLifecycleWatcher], backed by [WidgetsBinding].
final class WidgetsBindingLifecycleWatcher
    with WidgetsBindingObserver
    implements AppLifecycleWatcher {
  WidgetsBindingLifecycleWatcher(this._logger);

  final ConfigDirectorLogger _logger;

  void Function(AppLifecycleState state)? _onStateChanged;
  WidgetsBinding? _binding;

  @override
  void start(void Function(AppLifecycleState state) onStateChanged) {
    _onStateChanged = onStateChanged;

    try {
      _binding = WidgetsBinding.instance..addObserver(this);
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
    _binding?.removeObserver(this);
    _binding = null;
    _onStateChanged = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _onStateChanged?.call(state);
}
