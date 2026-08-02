import 'package:configdirector_flutter_sample_app/src/config_director_scope.dart';
import 'package:configdirector_flutter_sample_app/src/flags_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_client.dart';

void main() {
  testWidgets('shows the evaluated value of every config', (tester) async {
    final client = FakeConfigDirectorClient({
      'temporary-feature-flag': false,
      'permanent-kill-switch': true,
      'integer-config': 42,
      'day-of-the-week-config': 'Tuesday',
      'json-value-config': {'greeting': 'hello'},
    });
    addTearDown(client.dispose);

    await tester.pumpWidget(_wrap(client));
    await tester.pump();

    expect(find.text('OFF'), findsOneWidget); // temporary-feature-flag
    expect(find.text('ON'), findsOneWidget); // permanent-kill-switch
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.textContaining('"greeting": "hello"'), findsOneWidget);
  });

  testWidgets('falls back to the default value of every config', (
    tester,
  ) async {
    final client = FakeConfigDirectorClient();
    addTearDown(client.dispose);

    await tester.pumpWidget(_wrap(client));
    await tester.pump();

    expect(find.text('ON'), findsOneWidget); // temporary-feature-flag
    expect(find.text('OFF'), findsOneWidget); // permanent-kill-switch
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
  });
}

Widget _wrap(FakeConfigDirectorClient client) => ConfigDirectorScope(
  client: client,
  child: const MaterialApp(home: Scaffold(body: FlagsScreen())),
);
