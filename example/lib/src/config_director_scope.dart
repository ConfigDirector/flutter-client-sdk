import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:flutter/widgets.dart';

/// Makes the app's single [ConfigDirectorClient] available to the widgets below
/// it, so screens do not have to be handed the client explicitly.
///
/// ```dart
/// final client = ConfigDirectorScope.of(context);
/// ```
class ConfigDirectorScope extends InheritedWidget {
  const ConfigDirectorScope({
    required this.client,
    required super.child,
    super.key,
  });

  final ConfigDirectorClient client;

  /// The client of the closest [ConfigDirectorScope] above [context].
  static ConfigDirectorClient of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ConfigDirectorScope>();
    assert(scope != null, 'No ConfigDirectorScope found above this widget.');
    return scope!.client;
  }

  @override
  bool updateShouldNotify(ConfigDirectorScope oldWidget) =>
      client != oldWidget.client;
}
