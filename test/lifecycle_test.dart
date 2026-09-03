import 'package:configdirector_flutter_client_sdk/src/lifecycle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('reports lifecycle transitions until stopped', (tester) async {
    final states = <AppLifecycleState>[];
    final watcher = WidgetsBindingLifecycleWatcher(RecordingLogger())
      ..start(states.add);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    watcher.stop();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

    expect(states, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
  });
}
