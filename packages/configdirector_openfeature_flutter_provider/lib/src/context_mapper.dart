import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

ConfigDirectorContext mapEvaluationContext(EvaluationContext context) {
  final traits = context.getValue('traits');
  final anonymous = context.getValue('anonymous');

  return ConfigDirectorContext(
    id: context.targetingKey ?? context.getValue('id')?.toString(),
    name: context.getValue('name')?.toString(),
    traits: traits is Map<String, Object?> && traits.isNotEmpty
        ? _jsonCompatibleMap(traits)
        : null,
    anonymous: anonymous is bool ? anonymous : null,
  );
}

Map<String, Object?> _jsonCompatibleMap(Map<String, Object?> map) => {
  for (final entry in map.entries) entry.key: _jsonCompatible(entry.value),
};

Object? _jsonCompatible(Object? value) => switch (value) {
  DateTime() => value.toUtc().toIso8601String(),
  List<Object?>() => [for (final item in value) _jsonCompatible(item)],
  Map<String, Object?>() => _jsonCompatibleMap(value),
  _ => value,
};
