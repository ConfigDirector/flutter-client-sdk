import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:configdirector_openfeature_flutter_provider/src/resolution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

void main() {
  ConfigEvaluation evaluation(
    EvaluationReason reason, {
    String? valueId,
    Variation? variation,
  }) => ConfigEvaluation(
    key: 'a-key',
    value: 'value',
    valueId: valueId,
    variation: variation,
    isDefaultValue:
        reason != EvaluationReason.foundMatch &&
        reason != EvaluationReason.cached &&
        reason != EvaluationReason.rolloutSkippedNoIdentifier,
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

  test(
    'a value kept on the device is cached, with the value id as variant',
    () {
      final details = resolutionOf(
        evaluation(EvaluationReason.cached, valueId: 'value-id'),
        'value',
      );

      expect(details.value, 'value');
      expect(details.variant, 'value-id');
      expect(details.reason, 'CACHED');
      expect(details.errorCode, isNull);
      expect(details.errorMessage, isNull);
    },
  );

  test(
    'a served named variation is a targeting match with its name as variant',
    () {
      final details = resolutionOf(
        evaluation(
          EvaluationReason.foundMatch,
          valueId: 'value-id',
          variation: const Variation(id: 'variation-id', name: 'treatment'),
        ),
        'value',
      );

      expect(details.value, 'value');
      expect(details.variant, 'treatment');
      expect(details.reason, 'TARGETING_MATCH');
      expect(details.errorCode, isNull);
    },
  );

  test('a served unnamed variation has the value id as variant', () {
    final details = resolutionOf(
      evaluation(
        EvaluationReason.foundMatch,
        valueId: 'value-id',
        variation: const Variation(id: 'variation-id'),
      ),
      'value',
    );

    expect(details.variant, 'value-id');
    expect(details.reason, 'TARGETING_MATCH');
  });

  test('a named variation kept on the device is cached, with its name as '
      'variant', () {
    final details = resolutionOf(
      evaluation(
        EvaluationReason.cached,
        valueId: 'value-id',
        variation: const Variation(id: 'variation-id', name: 'treatment'),
      ),
      'value',
    );

    expect(details.variant, 'treatment');
    expect(details.reason, 'CACHED');
  });

  test('a skipped rollout resolves with the reason DEFAULT and the value id as '
      'variant', () {
    final details = resolutionOf(
      evaluation(
        EvaluationReason.rolloutSkippedNoIdentifier,
        valueId: 'value-id',
      ),
      'value',
    );

    expect(details.variant, 'value-id');
    expect(details.reason, 'DEFAULT');
    expect(details.errorCode, isNull);
  });

  test('a skipped rollout of a named variation has its name as variant', () {
    final details = resolutionOf(
      evaluation(
        EvaluationReason.rolloutSkippedNoIdentifier,
        valueId: 'value-id',
        variation: const Variation(id: 'variation-id', name: 'control'),
      ),
      'value',
    );

    expect(details.variant, 'control');
    expect(details.reason, 'DEFAULT');
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
