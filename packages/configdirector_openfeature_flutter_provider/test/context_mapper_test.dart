import 'dart:convert';

import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_openfeature_flutter_provider/src/context_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

void main() {
  test('maps an empty context to an empty ConfigDirector context', () {
    expect(
      mapEvaluationContext(EvaluationContext.empty),
      const ConfigDirectorContext(),
    );
  });

  test('maps the targeting key to the id', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(targetingKey: 'user-123'),
    );

    expect(mapped.id, 'user-123');
  });

  test('falls back to the id attribute without a targeting key', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(attributes: {'id': 42}),
    );

    expect(mapped.id, '42');
  });

  test('prefers the targeting key over the id attribute', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(targetingKey: 'user-123', attributes: {'id': 'other'}),
    );

    expect(mapped.id, 'user-123');
  });

  test('maps the name, traits and anonymous attributes', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(
        targetingKey: 'user-123',
        attributes: {
          'name': 'Ada',
          'anonymous': true,
          'traits': {
            'plan': 'pro',
            'seats': 5,
            'tags': ['a', 'b'],
          },
        },
      ),
    );

    expect(
      mapped,
      const ConfigDirectorContext(
        id: 'user-123',
        name: 'Ada',
        anonymous: true,
        traits: {
          'plan': 'pro',
          'seats': 5,
          'tags': ['a', 'b'],
        },
      ),
    );
  });

  test('ignores attributes ConfigDirector has no field for', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(targetingKey: 'user-123', attributes: {'plan': 'pro'}),
    );

    expect(mapped, const ConfigDirectorContext(id: 'user-123'));
  });

  test('leaves out traits that are empty or not a structure', () {
    expect(
      mapEvaluationContext(
        EvaluationContext(attributes: {'traits': <String, Object?>{}}),
      ).traits,
      isNull,
    );
    expect(
      mapEvaluationContext(
        EvaluationContext(attributes: {'traits': 'pro'}),
      ).traits,
      isNull,
    );
  });

  test('leaves out an anonymous attribute that is not a boolean', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(attributes: {'anonymous': 'yes'}),
    );

    expect(mapped.anonymous, isNull);
  });

  test('turns dates inside traits into UTC ISO 8601 strings', () {
    final mapped = mapEvaluationContext(
      EvaluationContext(
        attributes: {
          'traits': {
            'signedUpAt': DateTime.utc(2026, 1, 2, 3, 4, 5),
            'history': [
              {'at': DateTime.utc(2025, 12, 31)},
            ],
          },
        },
      ),
    );

    expect(mapped.traits, {
      'signedUpAt': '2026-01-02T03:04:05.000Z',
      'history': [
        {'at': '2025-12-31T00:00:00.000Z'},
      ],
    });
    expect(() => jsonEncode(mapped.toJson()), returnsNormally);
  });
}
