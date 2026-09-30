import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_flutter_client_sdk/testing.dart';
import 'package:configdirector_flutter_sample_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TestClient testClient;

  tearDown(() => testClient.client.dispose());

  Future<void> pumpHomePage(
    WidgetTester tester, {
    Map<String, Object?> values = const {},
    ConfigDirectorContext? context,
  }) async {
    testClient = createTestClient(values: values);
    await testClient.client.initialize(context);
    await tester.pumpWidget(
      ConfigDirectorScope(
        client: testClient.client,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the evaluated value of every config', (tester) async {
    await pumpHomePage(
      tester,
      values: {
        'temporary-feature-flag': false,
        'permanent-kill-switch': true,
        'integer-config': 42,
        'day-of-the-week-config': 'Tuesday',
        'json-value-config': {'greeting': 'hello'},
      },
    );

    expect(find.text('false'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text('{greeting: hello}'), findsOneWidget);
  });

  testWidgets('falls back to the default value of every config', (
    tester,
  ) async {
    await pumpHomePage(tester);

    expect(find.text('true'), findsOneWidget);
    expect(find.text('false'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
    expect(find.text('{}'), findsOneWidget);
  });

  testWidgets('re-renders a config when its value changes', (tester) async {
    await pumpHomePage(tester, values: {'integer-config': 42});
    expect(find.text('42'), findsOneWidget);

    testClient.setValue('integer-config', 7);
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('serves the default again when a config is removed', (
    tester,
  ) async {
    await pumpHomePage(tester, values: {'day-of-the-week-config': 'Tuesday'});
    expect(find.text('Tuesday'), findsOneWidget);

    testClient.removeValue('day-of-the-week-config');
    await tester.pumpAndSettle();

    expect(find.text('Friday'), findsOneWidget);
    expect(find.text('Tuesday'), findsNothing);
  });

  testWidgets('shows the context the configs were evaluated against', (
    tester,
  ) async {
    const context = ConfigDirectorContext(
      id: 'user-123',
      traits: {'role': 'admin'},
    );
    await pumpHomePage(tester, context: context);

    expect(find.textContaining('id: user-123'), findsOneWidget);
    expect(find.textContaining('traits: {role: admin}'), findsOneWidget);
    expect(testClient.contextUpdates, [context]);
  });

  testWidgets('says so when there is no context', (tester) async {
    await pumpHomePage(tester);

    expect(find.textContaining('No context'), findsOneWidget);
  });

  testWidgets('reports the connection while initialization is pending', (
    tester,
  ) async {
    testClient = createTestClient();
    testClient.holdInitialization();
    final initialized = testClient.client.initialize();
    await tester.pumpWidget(
      ConfigDirectorScope(
        client: testClient.client,
        child: const MaterialApp(home: HomePage()),
      ),
    );

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);

    testClient.completeInitialization();
    await initialized;
    await tester.pump();

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Connecting…'), findsNothing);
  });
}
