import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:configdirector_flutter_client_sdk/src/value_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ConfigState state(ConfigType type, String? value) => ConfigState(
  id: 'config-id',
  key: 'a-key',
  type: type,
  value: value,
  valueId: 'value-id',
);

void main() {
  group('parseConfigValue', () {
    test('returns the default value when the config has no value', () {
      final result = parseConfigValue(
        state(ConfigType.string, null),
        'fallback',
      );

      expect(result.value, 'fallback');
      expect(result.usedDefault, isTrue);
      expect(result.valueId, isNull);
      expect(result.reason, EvaluationReason.valueMissing);
    });

    test('returns the default value when the value is empty', () {
      final result = parseConfigValue(state(ConfigType.string, ''), 'fallback');

      expect(result.value, 'fallback');
      expect(result.reason, EvaluationReason.valueMissing);
    });

    group('string defaults', () {
      test('returns the raw value regardless of the config type', () {
        for (final type in ConfigType.values) {
          final result = parseConfigValue(state(type, '42'), 'fallback');

          expect(result.value, '42', reason: 'for ${type.wireName}');
          expect(result.usedDefault, isFalse);
          expect(result.valueId, 'value-id');
          expect(result.reason, EvaluationReason.foundMatch);
        }
      });
    });

    group('bool defaults', () {
      test('parses true and false case-insensitively', () {
        expect(
          parseConfigValue(state(ConfigType.boolean, 'true'), false).value,
          isTrue,
        );
        expect(
          parseConfigValue(state(ConfigType.boolean, 'TRUE'), false).value,
          isTrue,
        );
        expect(
          parseConfigValue(state(ConfigType.boolean, 'False'), true).value,
          isFalse,
        );
      });

      test('parses booleans out of string configs', () {
        final result = parseConfigValue(
          state(ConfigType.string, 'true'),
          false,
        );

        expect(result.value, isTrue);
        expect(result.reason, EvaluationReason.foundMatch);
      });

      test('falls back when the value is not a boolean', () {
        final result = parseConfigValue(
          state(ConfigType.boolean, 'yes'),
          false,
        );

        expect(result.value, isFalse);
        expect(result.usedDefault, isTrue);
        expect(result.valueId, isNull);
        expect(result.reason, EvaluationReason.invalidBoolean);
      });

      test('falls back on a type mismatch', () {
        final result = parseConfigValue(state(ConfigType.integer, '1'), false);

        expect(result.value, isFalse);
        expect(result.reason, EvaluationReason.typeMismatch);
      });
    });

    group('int defaults', () {
      test('parses integer configs', () {
        final result = parseConfigValue(state(ConfigType.integer, '42'), 0);

        expect(result.value, 42);
        expect(result.valueId, 'value-id');
        expect(result.reason, EvaluationReason.foundMatch);
      });

      test('truncates a float config so it can serve an int default', () {
        expect(parseConfigValue(state(ConfigType.float, '3.7'), 0).value, 3);
        expect(parseConfigValue(state(ConfigType.float, '-3.7'), 0).value, -3);
      });

      test('falls back when the value is not a number', () {
        final result = parseConfigValue(
          state(ConfigType.integer, 'not-a-number'),
          7,
        );

        expect(result.value, 7);
        expect(result.usedDefault, isTrue);
        expect(result.reason, EvaluationReason.invalidNumber);
      });

      test('falls back on a type mismatch', () {
        final result = parseConfigValue(state(ConfigType.boolean, 'true'), 7);

        expect(result.value, 7);
        expect(result.reason, EvaluationReason.typeMismatch);
      });
    });

    group('double defaults', () {
      test('parses float, enum, integer, and string configs', () {
        expect(
          parseConfigValue(state(ConfigType.float, '3.5'), 0.0).value,
          3.5,
        );
        expect(
          parseConfigValue(state(ConfigType.enumeration, '2'), 0.0).value,
          2.0,
        );
        expect(
          parseConfigValue(state(ConfigType.integer, '2'), 0.0).value,
          2.0,
        );
        expect(
          parseConfigValue(state(ConfigType.string, '1e2'), 0.0).value,
          100.0,
        );
      });

      test('falls back on non-finite values', () {
        final result = parseConfigValue(
          state(ConfigType.float, 'Infinity'),
          1.5,
        );

        expect(result.value, 1.5);
        expect(result.reason, EvaluationReason.invalidNumber);
      });
    });

    group('json configs', () {
      test('decodes an object into a map default', () {
        final result = parseConfigValue(
          state(ConfigType.json, '{"a":1,"b":[true]}'),
          const <String, dynamic>{},
        );

        expect(result.value, {
          'a': 1,
          'b': [true],
        });
        expect(result.usedDefault, isFalse);
        expect(result.reason, EvaluationReason.foundMatch);
      });

      test('decodes an array into a list default', () {
        final result = parseConfigValue(
          state(ConfigType.json, '[1,2]'),
          const <dynamic>[],
        );

        expect(result.value, [1, 2]);
        expect(result.reason, EvaluationReason.foundMatch);
      });

      test('returns the raw document for a string default', () {
        final result = parseConfigValue(
          state(ConfigType.json, '{"a":1}'),
          '{}',
        );

        expect(result.value, '{"a":1}');
        expect(result.reason, EvaluationReason.foundMatch);
      });

      test('falls back when the document is malformed', () {
        final result = parseConfigValue(
          state(ConfigType.json, '{not json'),
          const <String, dynamic>{'fallback': true},
        );

        expect(result.value, {'fallback': true});
        expect(result.usedDefault, isTrue);
        expect(result.reason, EvaluationReason.invalidJson);
      });

      test('falls back when the document decodes to another type', () {
        final result = parseConfigValue(
          state(ConfigType.json, '[1,2]'),
          const <String, dynamic>{},
        );

        expect(result.value, isEmpty);
        expect(result.usedDefault, isTrue);
        expect(result.reason, EvaluationReason.typeMismatch);
      });
    });

    test(
      'falls back when a structured default is used with a scalar config',
      () {
        final result = parseConfigValue(
          state(ConfigType.string, 'a-value'),
          const <String, dynamic>{},
        );

        expect(result.value, isEmpty);
        expect(result.reason, EvaluationReason.typeMismatch);
      },
    );
  });
}
