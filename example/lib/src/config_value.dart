import 'package:flutter/widgets.dart';

import 'config_director_scope.dart';

/// Builds a widget from the current value of [configKey] and rebuilds it every
/// time that value changes, either because the config was edited in the
/// ConfigDirector dashboard or because the context was updated.
///
/// `T` is inferred from [defaultValue], which is also what gets built until the
/// client is ready.
///
/// ```dart
/// ConfigValue<bool>(
///   configKey: 'dark-mode',
///   defaultValue: false,
///   builder: (context, darkMode) => Text('$darkMode'),
/// )
/// ```
class ConfigValue<T extends Object> extends StatefulWidget {
  const ConfigValue({
    required this.configKey,
    required this.defaultValue,
    required this.builder,
    super.key,
  });

  final String configKey;

  /// The value to build with until the config resolves to one of its own.
  final T defaultValue;

  final Widget Function(BuildContext context, T value) builder;

  @override
  State<ConfigValue<T>> createState() => _ConfigValueState<T>();
}

class _ConfigValueState<T extends Object> extends State<ConfigValue<T>> {
  /// `watch` hands out a new stream per call, so it is called when the inputs
  /// change rather than on every build, and the stream is held onto in between.
  late Stream<T> _values;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watch();
  }

  @override
  void didUpdateWidget(covariant ConfigValue<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.configKey != oldWidget.configKey ||
        widget.defaultValue != oldWidget.defaultValue) {
      _watch();
    }
  }

  void _watch() {
    _values = ConfigDirectorScope.of(
      context,
    ).watch(widget.configKey, widget.defaultValue);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _values,
      initialData: widget.defaultValue,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data ?? widget.defaultValue),
    );
  }
}
