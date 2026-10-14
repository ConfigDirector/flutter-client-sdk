import 'package:configdirector_flutter_client_sdk/src/context_admission.dart';
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
}
