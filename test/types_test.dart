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
  });
}
