import 'package:configdirector_flutter_client_sdk/src/context_admission.dart';
import 'package:configdirector_flutter_client_sdk/src/telemetry/telemetry_events.dart';
import 'package:configdirector_flutter_client_sdk/src/types.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher admits(ConfigDirectorContext? context) => isA<ContextAdmitted>().having(
  (admission) => admission.context,
  'context',
  same(context),
);

Matcher ignoresWithContextKindSample(String contextKindSample) =>
    isA<ContextIgnoredForAnInvalidContextKind>().having(
      (admission) => admission.contextKindSample,
      'contextKindSample',
      contextKindSample,
    );

Matcher ignoresOverSizeLimit(ContextSizeLimitReason reason) =>
    isA<ContextIgnoredOverASizeLimit>().having(
      (admission) => admission.reason,
      'reason',
      reason,
    );

Map<String, Object?> traitsOfJsonBytes(int jsonBytes) => {
  'note': 'x' * (jsonBytes - '{"note":""}'.length),
};

void main() {
  test('admits a context without a context kind', () {
    const context = ConfigDirectorContext(id: '42');

    expect(admissionOf(context), admits(context));
  });

  test('admits no context', () {
    expect(admissionOf(null), admits(null));
  });

  test('admits a context kind of lowercase letters, digits, dashes and '
      'underscores', () {
    const context = ConfigDirectorContext(id: '42', kind: 'a-z_0-9');

    expect(admissionOf(context), admits(context));
  });

  test('admits a context kind of 64 characters', () {
    final context = ConfigDirectorContext(id: '42', kind: 'd' * 64);

    expect(admissionOf(context), admits(context));
  });

  test('ignores an empty context kind', () {
    const context = ConfigDirectorContext(id: '42', kind: '');

    expect(admissionOf(context), ignoresWithContextKindSample(''));
  });

  test('ignores a context kind of 65 characters', () {
    final context = ConfigDirectorContext(id: '42', kind: 'd' * 65);

    expect(admissionOf(context), ignoresWithContextKindSample('d' * 65));
  });

  test('ignores a context kind with an uppercase letter', () {
    const context = ConfigDirectorContext(id: '42', kind: 'Device');

    expect(admissionOf(context), ignoresWithContextKindSample('Device'));
  });

  test('ignores a context kind it would have to trim', () {
    const context = ConfigDirectorContext(id: '42', kind: 'device ');

    expect(admissionOf(context), ignoresWithContextKindSample('device '));
  });

  test('ignores a context kind with a letter outside ASCII', () {
    const context = ConfigDirectorContext(id: '42', kind: 'dévice');

    expect(admissionOf(context), ignoresWithContextKindSample('dévice'));
  });

  test('samples the first 128 characters of a longer context kind', () {
    final context = ConfigDirectorContext(id: '42', kind: 'D' * 129);

    expect(admissionOf(context), ignoresWithContextKindSample('D' * 128));
  });

  test('cuts the context kind sample on a character boundary', () {
    final context = ConfigDirectorContext(id: '42', kind: '😀' * 129);

    expect(admissionOf(context), ignoresWithContextKindSample('😀' * 128));
  });

  test('ignores a context whose id has 257 characters, for '
      'identifier-too-long', () {
    final context = ConfigDirectorContext(id: 'i' * 257);

    expect(
      admissionOf(context),
      ignoresOverSizeLimit(ContextSizeLimitReason.identifierTooLong),
    );
  });

  test('admits a context whose id has 256 characters', () {
    final context = ConfigDirectorContext(id: 'i' * 256);

    expect(admissionOf(context), admits(context));
  });

  test('admits a context whose id has 200 emoji, since each emoji counts as '
      'one character', () {
    final context = ConfigDirectorContext(id: '😀' * 200);

    expect(admissionOf(context), admits(context));
  });

  test(
    'ignores a context whose name has 257 characters, for name-too-long',
    () {
      final context = ConfigDirectorContext(id: '42', name: 'n' * 257);

      expect(
        admissionOf(context),
        ignoresOverSizeLimit(ContextSizeLimitReason.nameTooLong),
      );
    },
  );

  test('admits a context whose name has 256 characters', () {
    final context = ConfigDirectorContext(id: '42', name: 'n' * 256);

    expect(admissionOf(context), admits(context));
  });

  test('ignores a context whose traits take 65,537 bytes of JSON, for '
      'traits-too-large', () {
    final context = ConfigDirectorContext(
      id: '42',
      traits: traitsOfJsonBytes(65537),
    );

    expect(
      admissionOf(context),
      ignoresOverSizeLimit(ContextSizeLimitReason.traitsTooLarge),
    );
  });

  test('admits a context whose traits take exactly 65,536 bytes of JSON', () {
    final context = ConfigDirectorContext(
      id: '42',
      traits: traitsOfJsonBytes(65536),
    );

    expect(admissionOf(context), admits(context));
  });

  test('ignores a context whose traits have fewer than 65,536 characters but '
      'take more than 65,536 bytes of JSON', () {
    final context = ConfigDirectorContext(
      id: '42',
      traits: {'note': 'é' * 40000},
    );

    expect(
      admissionOf(context),
      ignoresOverSizeLimit(ContextSizeLimitReason.traitsTooLarge),
    );
  });

  test('admits a context whose traits cannot be written as JSON', () {
    final context = ConfigDirectorContext(
      id: '42',
      traits: {'signedUpAt': DateTime.utc(2026, 11, 25)},
    );

    expect(admissionOf(context), admits(context));
  });

  test('ignores a context over the id and the traits limits for '
      'identifier-too-long', () {
    final context = ConfigDirectorContext(
      id: 'i' * 257,
      traits: traitsOfJsonBytes(65537),
    );

    expect(
      admissionOf(context),
      ignoresOverSizeLimit(ContextSizeLimitReason.identifierTooLong),
    );
  });

  test('ignores a context over the id and the name limits for '
      'identifier-too-long', () {
    final context = ConfigDirectorContext(id: 'i' * 257, name: 'n' * 257);

    expect(
      admissionOf(context),
      ignoresOverSizeLimit(ContextSizeLimitReason.identifierTooLong),
    );
  });

  test('ignores a context over the name and the traits limits for '
      'name-too-long', () {
    final context = ConfigDirectorContext(
      id: '42',
      name: 'n' * 257,
      traits: traitsOfJsonBytes(65537),
    );

    expect(
      admissionOf(context),
      ignoresOverSizeLimit(ContextSizeLimitReason.nameTooLong),
    );
  });

  test('ignores a context with an invalid context kind and an id over the '
      'limit for its context kind', () {
    final context = ConfigDirectorContext(id: 'i' * 257, kind: 'Device');

    expect(admissionOf(context), ignoresWithContextKindSample('Device'));
  });
}
