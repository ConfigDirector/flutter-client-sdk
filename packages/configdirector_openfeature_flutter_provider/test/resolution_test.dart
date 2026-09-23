import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_openfeature_flutter_provider/src/resolution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

void main() {
  ConfigEvaluation evaluation(EvaluationReason reason, {String? valueId}) =>
      ConfigEvaluation(
        key: 'a-key',
        value: 'value',
        valueId: valueId,
        isDefaultValue: reason != EvaluationReason.foundMatch,
        reason: reason,
      );

  test('a served value is a targeting match with the value id as variant', () {
    final details = resolutionOf(
      evaluation(EvaluationReason.foundMatch, valueId: 'value-id'),
      'value',
    );

    expect(details.value, 'value');
    expect(details.variant, 'value-id');
    expect(details.reason, 'TARGETING_MATCH');
    expect(details.errorCode, isNull);
    expect(details.errorMessage, isNull);
  });

  test('a config without a value resolves to the default', () {
    final details = resolutionOf(
      evaluation(EvaluationReason.valueMissing),
      'value',
    );

    expect(details.reason, 'DEFAULT');
    expect(details.variant, isNull);
    expect(details.errorCode, isNull);
  });

  test('maps every remaining reason to an error code', () {
    const expected = {
      EvaluationReason.configStateMissing: ErrorCode.flagNotFound,
      EvaluationReason.clientNotReady: ErrorCode.providerNotReady,
      EvaluationReason.typeMismatch: ErrorCode.typeMismatch,
      EvaluationReason.invalidBoolean: ErrorCode.typeMismatch,
      EvaluationReason.invalidNumber: ErrorCode.typeMismatch,
      EvaluationReason.invalidJson: ErrorCode.typeMismatch,
    };

    for (final entry in expected.entries) {
      final details = resolutionOf(evaluation(entry.key), 'value');

      expect(details.errorCode, entry.value, reason: entry.key.name);
      expect(details.reason, 'ERROR', reason: entry.key.name);
      expect(details.errorMessage, isNotEmpty, reason: entry.key.name);
      expect(details.variant, isNull, reason: entry.key.name);
    }
  });

  test('names the reason a value could not be read', () {
    final details = resolutionOf(
      evaluation(EvaluationReason.invalidJson),
      'value',
    );

    expect(details.errorMessage, contains('invalid-json'));
    expect(details.errorMessage, contains("'a-key'"));
  });
}
