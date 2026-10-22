import 'package:configdirector_flutter_client_sdk/src/errors.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/value_id.dart';
import 'package:configdirector_flutter_client_sdk/src/native_value_encoder.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('type from the value', () {
    test('a bool is a boolean config', () {
      final state = encodeNativeValue('k', true);

      expect(state.type, ConfigType.boolean);
      expect(state.value, 'true');
    });

    test('an int is an integer config', () {
      final state = encodeNativeValue('k', 20);

      expect(state.type, ConfigType.integer);
      expect(state.value, '20');
    });

    test('a negative int keeps its sign', () {
      expect(encodeNativeValue('k', -7).value, '-7');
    });

    test('a non-integral double is a float config', () {
      final state = encodeNativeValue('k', 2.5);

      expect(state.type, ConfigType.float);
      expect(state.value, '2.5');
    });

    test(
      'an integral double is a float on the VM and an integer on the web',
      () {
        final state = encodeNativeValue('k', 2.0);

        if (kIsWeb) {
          expect(state.type, ConfigType.integer);
          expect(state.value, '2');
        } else {
          expect(state.type, ConfigType.float);
          expect(state.value, '2.0');
        }
      },
    );

    test('a String is a string config, even when it spells JSON', () {
      final state = encodeNativeValue('k', '{"a":1}');

      expect(state.type, ConfigType.string);
      expect(state.value, '{"a":1}');
    });

    test('a Map is a JSON config in insertion order', () {
      final state = encodeNativeValue('k', {
        'zebra': 1,
        'apple': [1, 2.5, 'x', null, true],
        'nested': {'b': 2, 'a': 1},
      });

      expect(state.type, ConfigType.json);
      expect(
        state.value,
        '{"zebra":1,"apple":[1,2.5,"x",null,true],"nested":{"b":2,"a":1}}',
      );
    });

    test('a List is a JSON config', () {
      final state = encodeNativeValue('k', ['x', 2, false]);

      expect(state.type, ConfigType.json);
      expect(state.value, '["x",2,false]');
    });

    test('a decoded JSON map with dynamic values is accepted', () {
      final Map<String, dynamic> decoded = {'greeting': 'hello'};

      expect(encodeNativeValue('k', decoded).value, '{"greeting":"hello"}');
    });

    test('keeps non-ASCII text as it is', () {
      expect(encodeNativeValue('k', {'g': 'héllo ✓'}).value, '{"g":"héllo ✓"}');
      expect(encodeNativeValue('k', 'héllo ✓').value, 'héllo ✓');
    });
  });

  group('numbers', () {
    test('a small float is written in plain notation', () {
      expect(encodeNativeValue('k', 1e-7).value, '0.0000001');
      expect(encodeNativeValue('k', 1.5e-7).value, '0.00000015');
      expect(encodeNativeValue('k', -2.5e-8).value, '-0.000000025');
    });

    test(
      'a large float is written in plain notation on the VM',
      () {
        expect(encodeNativeValue('k', 1e21).value, '1000000000000000000000.0');
        expect(
          encodeNativeValue('k', 1.2345e22).value,
          '12345000000000000000000.0',
        );
        expect(
          encodeNativeValue('k', -1.5e21).value,
          '-1500000000000000000000.0',
        );
      },
      skip: kIsWeb ? 'On the web these values are unsafe integers' : false,
    );

    test('expandExponent leaves plain text alone', () {
      expect(expandExponent('2.5'), '2.5');
      expect(expandExponent('-0.0'), '-0.0');
      expect(expandExponent('100.0'), '100.0');
    });

    test(
      'a large int is written in digits on the VM',
      () {
        expect(
          encodeNativeValue('k', 9007199254740992).value,
          '9007199254740992',
        );
      },
      skip: kIsWeb ? 'On the web the value cannot be represented' : false,
    );

    test(
      'an int beyond the safe range is rejected on the web',
      () {
        expect(
          () => encodeNativeValue('k', 9007199254740992),
          throwsA(isA<ConfigDirectorValidationException>()),
        );
        expect(
          () => encodeNativeValue('k', {
            'n': [9007199254740992],
          }),
          throwsA(isA<ConfigDirectorValidationException>()),
        );
      },
      skip: kIsWeb ? false : 'Only Dart compiled to JavaScript loses precision',
    );

    test('the largest safe integer is accepted everywhere', () {
      expect(
        encodeNativeValue('k', 9007199254740991).value,
        '9007199254740991',
      );
      expect(
        encodeNativeValue('k', -9007199254740991).value,
        '-9007199254740991',
      );
    });
  });

  group('rejected input', () {
    test('a null value', () {
      expect(
        () => encodeNativeValue('k', null),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('an empty key', () {
      expect(
        () => encodeNativeValue('', true),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('a key of only whitespace', () {
      expect(
        () => encodeNativeValue('   ', true),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('NaN', () {
      expect(
        () => encodeNativeValue('k', double.nan),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('infinity', () {
      expect(
        () => encodeNativeValue('k', double.infinity),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('negative infinity', () {
      expect(
        () => encodeNativeValue('k', double.negativeInfinity),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('a non-finite number inside a JSON document', () {
      expect(
        () => encodeNativeValue('k', {'n': double.infinity}),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('an unsupported type', () {
      expect(
        () => encodeNativeValue('k', DateTime(2026)),
        throwsA(
          isA<ConfigDirectorValidationException>().having(
            (error) => error.message,
            'message',
            contains('DateTime'),
          ),
        ),
      );
      expect(
        () => encodeNativeValue('k', {1, 2}),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('unsupported JSON contents', () {
      expect(
        () => encodeNativeValue('k', {'when': DateTime(2026)}),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
      expect(
        () => encodeNativeValue('k', [
          {1, 2},
        ]),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });

    test('a map with a non-String key', () {
      expect(
        () => encodeNativeValue('k', {1: 'one'}),
        throwsA(
          isA<ConfigDirectorValidationException>().having(
            (error) => error.message,
            'message',
            contains('String'),
          ),
        ),
      );
      expect(
        () => encodeNativeValue('k', {
          'outer': {2: 'two'},
        }),
        throwsA(isA<ConfigDirectorValidationException>()),
      );
    });
  });

  group('identifiers', () {
    test('the value id is the id ConfigDirector derives from the text', () {
      final state = encodeNativeValue('k', {'a': 1});

      expect(state.valueId, generateValueId('{"a":1}'));
    });

    test('every config gets its own id and keeps its key', () {
      final first = encodeNativeValue('k', true);
      final second = encodeNativeValue('k', true);

      expect(first.key, 'k');
      expect(first.id, isNotEmpty);
      expect(first.id, isNot(second.id));
    });
  });
}
