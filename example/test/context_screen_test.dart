import 'package:configdirector_flutter_sample_app/src/config_director_scope.dart';
import 'package:configdirector_flutter_sample_app/src/context_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_client.dart';

void main() {
  testWidgets('saving sends what was typed in as the new context', (
    tester,
  ) async {
    final client = FakeConfigDirectorClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_wrap(client));

    await tester.enterText(find.byType(TextField).at(0), 'user-123');
    await tester.enterText(find.byType(TextField).at(1), 'Jane Smith');
    await tester.enterText(find.byType(TextField).at(2), 'admin');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(client.updatedContexts, hasLength(1));
    expect(client.updatedContexts.single.id, 'user-123');
    expect(client.updatedContexts.single.name, 'Jane Smith');
    expect(client.updatedContexts.single.traits, {'role': 'admin'});
    expect(find.text('Context saved'), findsOneWidget);
    expect(find.textContaining('id: user-123'), findsOneWidget);
  });

  testWidgets('clearing empties the fields and the context', (tester) async {
    final client = FakeConfigDirectorClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_wrap(client));

    await tester.enterText(find.byType(TextField).at(0), 'user-123');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(client.updatedContexts.single.id, isNull);
    expect(client.updatedContexts.single.traits, isNull);
    expect(find.text('user-123'), findsNothing);
    expect(find.text('Context cleared'), findsOneWidget);
  });
}

Widget _wrap(FakeConfigDirectorClient client) => ConfigDirectorScope(
  client: client,
  child: const MaterialApp(home: Scaffold(body: ContextScreen())),
);
