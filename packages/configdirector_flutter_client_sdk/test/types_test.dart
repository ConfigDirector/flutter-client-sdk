import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the traits at runtime so nested collections are distinct instances,
/// unlike `const` literals, which Dart canonicalizes into one shared object.
Map<String, Object?> traitsFor(String country) => {
  'plan': 'pro',
  'flags': ['beta', 'labs'],
  'address': {'country': country},
};

void main() {
  group('ConfigDirectorContext', () {
    test('compares nested traits by value', () {
      final a = ConfigDirectorContext(id: 'user-1', traits: traitsFor('AR'));
      final b = ConfigDirectorContext(id: 'user-1', traits: traitsFor('AR'));

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when a nested trait differs', () {
      final a = ConfigDirectorContext(id: 'user-1', traits: traitsFor('AR'));
      final b = ConfigDirectorContext(id: 'user-1', traits: traitsFor('UY'));

      expect(a, isNot(equals(b)));
    });

    test('serializes its context kind', () {
      const context = ConfigDirectorContext(id: '42', kind: 'device');

      expect(context.toJson(), {'id': '42', 'kind': 'device'});
    });

    test('leaves the context kind out when none was given', () {
      const context = ConfigDirectorContext(id: '42');

      expect(context.toJson(), {'id': '42'});
    });

    test('keeps an invalid context kind as given', () {
      const context = ConfigDirectorContext(kind: ' Tenant');

      expect(context.kind, ' Tenant');
    });

    test('tells contexts apart by their context kind', () {
      final device = ConfigDirectorContext(id: '42', kind: 'device');
      final sameDevice = ConfigDirectorContext(id: '42', kind: 'device');
      final tenant = ConfigDirectorContext(id: '42', kind: 'tenant');

      expect(device, equals(sameDevice));
      expect(device.hashCode, sameDevice.hashCode);
      expect(device, isNot(equals(tenant)));
    });

    test('tells a context without a context kind apart from one of context '
        'kind user', () {
      const explicitUser = ConfigDirectorContext(id: '42', kind: 'user');
      const withoutContextKind = ConfigDirectorContext(id: '42');

      expect(explicitUser, isNot(equals(withoutContextKind)));
    });

    test('describes its context kind next to its id', () {
      const context = ConfigDirectorContext(id: '42', kind: 'device');

      expect(
        context.toString(),
        'ConfigDirectorContext(id: 42, kind: device, name: null, '
        'traits: null, anonymous: null)',
      );
    });
  });
}
