import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_sample_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_client.dart';

void main() {
  testWidgets('shows the evaluated value of every config', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FakeConfigDirectorClient(
          values: {
            'temporary-feature-flag': false,
            'permanent-kill-switch': true,
            'integer-config': 42,
            'day-of-the-week-config': 'Tuesday',
            'json-value-config': {'greeting': 'hello'},
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('false'), findsOneWidget); // temporary-feature-flag
    expect(find.text('true'), findsOneWidget); // permanent-kill-switch
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('{greeting: hello}'), findsOneWidget);
  });

  testWidgets('falls back to the default value of every config', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(FakeConfigDirectorClient()));
    await tester.pump();

    expect(find.text('true'), findsOneWidget); // temporary-feature-flag
    expect(find.text('false'), findsOneWidget); // permanent-kill-switch
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
  });

  testWidgets('shows the context the configs were evaluated against', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FakeConfigDirectorClient(
          context: const ConfigDirectorContext(
            id: 'user-123',
            traits: {'role': 'admin'},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('id: user-123'), findsOneWidget);
    expect(find.textContaining('traits: {role: admin}'), findsOneWidget);
  });

  testWidgets('says so when there is no context', (tester) async {
    await tester.pumpWidget(_wrap(FakeConfigDirectorClient()));
    await tester.pump();

    expect(find.textContaining('No context'), findsOneWidget);
  });
}

Widget _wrap(FakeConfigDirectorClient client) => ConfigDirectorScope(
  client: client,
  child: const MaterialApp(home: HomePage()),
);
