import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

String? _variantOf(ConfigEvaluation evaluation) =>
    evaluation.variation?.name ?? evaluation.valueId;

ResolutionDetails<T> resolutionOf<T extends Object>(
  ConfigEvaluation evaluation,
  T value,
) => switch (evaluation.reason) {
  EvaluationReason.foundMatch => ResolutionDetails(
    value: value,
    variant: _variantOf(evaluation),
    reason: 'TARGETING_MATCH',
  ),
  EvaluationReason.cached => ResolutionDetails(
    value: value,
    variant: _variantOf(evaluation),
    reason: 'CACHED',
  ),
  EvaluationReason.rolloutSkippedNoIdentifier => ResolutionDetails(
    value: value,
    variant: _variantOf(evaluation),
    reason: 'DEFAULT',
  ),
  EvaluationReason.valueMissing => ResolutionDetails(
    value: value,
    reason: 'DEFAULT',
  ),
  EvaluationReason.configStateMissing => _error(
    value,
    ErrorCode.flagNotFound,
    "No config with the key '${evaluation.key}' was found.",
  ),
  EvaluationReason.clientNotReady => _error(
    value,
    ErrorCode.providerNotReady,
    'ConfigDirector has not delivered config state yet.',
  ),
  EvaluationReason.typeMismatch ||
  EvaluationReason.invalidBoolean ||
  EvaluationReason.invalidNumber ||
  EvaluationReason.invalidJson => _error(
    value,
    ErrorCode.typeMismatch,
    "The value of '${evaluation.key}' cannot be read as the requested type "
    '(${evaluation.reason.wireName}).',
  ),
};

ResolutionDetails<T> _error<T extends Object>(
  T value,
  ErrorCode errorCode,
  String message,
) => ResolutionDetails(
  value: value,
  errorCode: errorCode,
  errorMessage: message,
  reason: 'ERROR',
);
