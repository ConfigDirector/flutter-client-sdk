import 'package:configdirector_openfeature_flutter_sample_app/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

void main() {
  tearDown(() => OpenFeatureAPI.instance.shutdown());

  testWidgets('shows the values the provider resolves', (tester) async {
    await tester.pumpWidget(
      SampleApp(
        provider: InMemoryProvider({
          'temporary-feature-flag': true,
          'integer-config': 42,
          'day-of-the-week-config': 'friday',
        }),
        context: EvaluationContext(targetingKey: 'user-123'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ready'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('friday'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(OpenFeatureAPI.instance.shutdown);
  });

  testWidgets('asks for a key when there is no provider', (tester) async {
    await tester.pumpWidget(
      const SampleApp(provider: null, context: EvaluationContext.empty),
    );

    expect(find.textContaining('CONFIGDIRECTOR_SDK_KEY'), findsOneWidget);
  });
}
