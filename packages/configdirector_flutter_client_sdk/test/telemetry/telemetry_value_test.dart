import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_events.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_value.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/value_id.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateValueId', () {
    // The ids below come from the JavaScript SDKs: every ConfigDirector SDK has
    // to derive the same id for the same value, or the dashboard would count
    // the same value twice.
    test('matches the ids the other SDKs generate', () {
      expect(generateValueId('hello'), '1MoOW7eqAPjhZeoELVwO9G');
      expect(generateValueId(''), '6ve2WrOl3mnciB6WIL2fIa');
      expect(generateValueId('{"a":1}'), '02YSZ1nYJC4FpTxtj1zjMu');
      expect(generateValueId('a' * 600), '5fN8d72HXaUK6VkcOwuKTN');
    });

    test('reports a value by the string it serializes to', () {
      expect(generateValueId(true), generateValueId('true'));
      expect(generateValueId(42), generateValueId('42'));
      expect(generateValueId(null), generateValueId(''));
    });

    test('is always the same length', () {
      for (final value in ['hello', '', 'a' * 600, '\u{1F600}']) {
        expect(generateValueId(value).length, 22, reason: value);
      }
    });
  });

  group('TelemetryValue.of', () {
    test('reports a small value inline', () {
      expect(
        TelemetryValue.of(true, type: ConfigType.boolean),
        const TelemetryValue(value: 'true'),
      );
      expect(
        TelemetryValue.of(25, type: ConfigType.integer),
        const TelemetryValue(value: '25'),
      );
    });

    test('prefers the value over the id the server sent', () {
      expect(
        TelemetryValue.of('hello', valueId: 'server-id'),
        const TelemetryValue(value: 'hello'),
      );
    });

    test('reports a value too large to send by id', () {
      final value = 'a' * (configValueMaxLength + 1);

      expect(
        TelemetryValue.of(value, valueId: 'server-id'),
        const TelemetryValue(valueId: 'server-id'),
      );
      expect(TelemetryValue.of(value), TelemetryValue(value: value));
    });

    test('encodes a JSON config', () {
      expect(
        TelemetryValue.of({'a': 1}, type: ConfigType.json),
        const TelemetryValue(value: '{"a":1}', type: ConfigType.json),
      );
      expect(
        TelemetryValue.of(
          {'a': 1},
          valueId: 'server-id',
          type: ConfigType.json,
        ),
        const TelemetryValue(valueId: 'server-id', type: ConfigType.json),
      );
    });

    test('treats a structured value with no declared type as JSON', () {
      expect(
        TelemetryValue.of(const [1, 2]),
        const TelemetryValue(value: '[1,2]', type: ConfigType.json),
      );
    });

    test('falls back to the value description when it cannot be encoded', () {
      expect(
        TelemetryValue.of([Object()], type: ConfigType.json).value,
        startsWith('[Instance of'),
      );
    });
  });

  group('TelemetryValue.compacted', () {
    test('keeps a small value and drops what is not reported', () {
      expect(
        const TelemetryValue(
          value: 'hello',
          type: ConfigType.string,
        ).compacted(),
        const TelemetryValue(value: 'hello'),
      );
    });

    test('keeps the id the server sent', () {
      expect(
        const TelemetryValue(valueId: 'server-id').compacted(),
        const TelemetryValue(valueId: 'server-id'),
      );
    });

    test('replaces a value too large to send with its id', () {
      final value = 'a' * (configValueMaxLength + 1);

      expect(
        TelemetryValue(value: value).compacted(),
        TelemetryValue(valueId: generateValueId(value)),
      );
    });

    test('replaces a JSON document with its id, however small', () {
      expect(
        const TelemetryValue(
          value: '{"a":1}',
          type: ConfigType.json,
        ).compacted(),
        TelemetryValue(valueId: generateValueId('{"a":1}')),
      );
    });
  });

  group('requestedTypeOf', () {
    test('reports the type the caller asked for', () {
      expect(requestedTypeOf('hi'), 'String');
      expect(requestedTypeOf(false), 'bool');
      expect(requestedTypeOf(1), 'int');
      expect(requestedTypeOf(1.5), 'double');
      expect(requestedTypeOf<num>(1), 'num');
      expect(requestedTypeOf(const {'a': 1}), 'Map');
      expect(requestedTypeOf(const [1]), 'List');
    });

    test('reports an int default as an int on every platform', () {
      // On the web `1.0 is int` holds, so the runtime type cannot be trusted.
      expect(requestedTypeOf<int>(1), 'int');
      expect(requestedTypeOf<double>(1), 'double');
    });
  });

  group('EvaluatedConfigEvent', () {
    test('collapses identical events and separates different ones', () {
      EvaluatedConfigEvent event({
        String key = 'dark-mode',
        bool value = true,
      }) => EvaluatedConfigEvent.fromEvaluation(
        key: key,
        type: ConfigType.boolean,
        defaultValue: false,
        evaluatedValue: value,
        requestedType: 'bool',
        usedDefault: false,
        evaluationReason: EvaluationReason.foundMatch,
      );

      expect(event(), event());
      expect(event().hashCode, event().hashCode);
      expect(event(), isNot(event(key: 'other')));
      expect(event(), isNot(event(value: false)));
    });

    test('serializes an evaluation for the server', () {
      final event = EvaluatedConfigEvent.fromEvaluation(
        contextId: 'user-123',
        key: 'max-items',
        type: ConfigType.integer,
        defaultValue: 10,
        evaluatedValue: 25,
        evaluatedValueId: 'server-id',
        requestedType: 'int',
        usedDefault: false,
        evaluationReason: EvaluationReason.foundMatch,
      );

      expect(event.compacted().toJson(), {
        'contextId': 'user-123',
        'key': 'max-items',
        'type': 'integer',
        'defaultValue': {'value': '10'},
        'requestedType': 'int',
        'evaluatedValue': {'value': '25'},
        'evaluatedValueId': 'server-id',
        'usedDefault': false,
        'evaluationReason': 'found-match',
      });
    });

    test('omits what an evaluation without config state does not have', () {
      final event = EvaluatedConfigEvent.fromEvaluation(
        key: 'dark-mode',
        defaultValue: false,
        evaluatedValue: false,
        requestedType: 'bool',
        usedDefault: true,
        evaluationReason: EvaluationReason.clientNotReady,
      );

      expect(event.compacted().toJson(), {
        'key': 'dark-mode',
        'defaultValue': {'value': 'false'},
        'requestedType': 'bool',
        'evaluatedValue': {'value': 'false'},
        'usedDefault': true,
        'evaluationReason': 'client-not-ready',
      });
    });
  });
}
