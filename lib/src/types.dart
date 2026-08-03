import 'package:flutter/foundation.dart';

/// The type a config was declared with in the ConfigDirector dashboard.
enum ConfigType {
  custom('custom'),
  boolean('boolean'),
  string('string'),
  integer('integer'),
  float('float'),
  enumeration('enum'),
  url('url'),
  json('json');

  const ConfigType(this.wireName);

  /// The value used to represent this type on the wire.
  final String wireName;

  /// Resolves a wire value to a [ConfigType], falling back to [ConfigType.custom]
  /// for types this SDK version does not know about.
  static ConfigType fromWireName(String? wireName) {
    for (final type in values) {
      if (type.wireName == wireName) {
        return type;
      }
    }
    return ConfigType.custom;
  }
}

/// The evaluated state of a single config, as returned by the server.
@immutable
final class ConfigState {
  const ConfigState({
    required this.id,
    required this.key,
    required this.type,
    this.value,
    this.valueId,
  });

  factory ConfigState.fromJson(Map<String, Object?> json) => ConfigState(
    id: json['id'] as String? ?? '',
    key: json['key'] as String? ?? '',
    type: ConfigType.fromWireName(json['type'] as String?),
    value: json['value'] as String?,
    valueId: json['valueId'] as String?,
  );

  final String id;
  final String key;
  final ConfigType type;

  /// The evaluated value, serialized as a string. It is `null` when the config
  /// has no value for the current context.
  final String? value;

  /// An opaque identifier of the evaluated value, used for telemetry.
  final String? valueId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConfigState &&
          other.id == id &&
          other.key == key &&
          other.type == type &&
          other.value == value &&
          other.valueId == valueId);

  @override
  int get hashCode => Object.hash(id, key, type, value, valueId);

  @override
  String toString() =>
      'ConfigState(id: $id, key: $key, type: ${type.wireName}, value: $value, valueId: $valueId)';
}

/// Whether a [ConfigSet] carries the complete config state or only the configs
/// that changed since the last one.
enum ConfigSetKind {
  full('full'),
  delta('delta');

  const ConfigSetKind(this.wireName);

  final String wireName;

  static ConfigSetKind fromWireName(String? wireName) =>
      wireName == delta.wireName ? delta : full;
}

/// A batch of config state received from the ConfigDirector server.
@immutable
final class ConfigSet {
  const ConfigSet({
    required this.environmentId,
    required this.projectId,
    required this.configs,
    required this.kind,
    this.timestamp,
  });

  factory ConfigSet.fromJson(Map<String, Object?> json) {
    final configs = <String, ConfigState>{};
    final rawConfigs = json['configs'];
    if (rawConfigs is Map) {
      for (final entry in rawConfigs.entries) {
        final rawState = entry.value;
        if (rawState is Map<String, Object?>) {
          configs[entry.key as String] = ConfigState.fromJson(rawState);
        }
      }
    }

    return ConfigSet(
      environmentId: json['environmentId'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      configs: Map.unmodifiable(configs),
      kind: ConfigSetKind.fromWireName(json['kind'] as String?),
      timestamp: json['timestamp'] as String?,
    );
  }

  final String environmentId;
  final String projectId;
  final Map<String, ConfigState> configs;
  final ConfigSetKind kind;

  /// The server timestamp of this set, echoed back on the next polling request
  /// so the server can respond with a delta.
  final String? timestamp;

  /// Returns a full set with [other]'s configs applied on top of this one's.
  ConfigSet mergedWith(ConfigSet other) => ConfigSet(
    environmentId: other.environmentId,
    projectId: other.projectId,
    configs: Map.unmodifiable({...configs, ...other.configs}),
    kind: ConfigSetKind.full,
    timestamp: other.timestamp ?? timestamp,
  );

  @override
  String toString() =>
      'ConfigSet(environmentId: $environmentId, projectId: $projectId, '
      'kind: ${kind.wireName}, keys: ${configs.keys.toList()})';
}

/// The user's context, sent to ConfigDirector and used to evaluate targeting
/// rules.
@immutable
final class ConfigDirectorContext {
  const ConfigDirectorContext({
    this.id,
    this.name,
    this.traits,
    this.anonymous,
  });

  /// The user's identifier. This should be a value that uniquely identifies an
  /// application user.
  ///
  /// For anonymous users you may generate a UUID, or leave this unset and let
  /// the SDK generate a random one. Keep in mind that this value is used to
  /// segment users in percentage rollouts, so changing it can move a user into
  /// a different percentile.
  final String? id;

  /// The user's display name. It is shown in the ConfigDirector dashboard and
  /// may be used by targeting rules.
  final String? name;

  /// Arbitrary traits for the current user. They are shown in the
  /// ConfigDirector dashboard and may be used by targeting rules.
  final Map<String, Object?>? traits;

  /// Whether to treat this context as anonymous during evaluation. When `true`,
  /// the values are still used to evaluate targeting rules, but the context is
  /// not persisted and does not appear in the dashboard.
  ///
  /// Defaults to `false` on the server when omitted.
  final bool? anonymous;

  /// The wire representation sent to the ConfigDirector server. Fields left
  /// unset are omitted rather than sent as `null`.
  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    if (name != null) 'name': name,
    if (traits != null) 'traits': traits,
    if (anonymous != null) 'anonymous': anonymous,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConfigDirectorContext &&
          other.id == id &&
          other.name == name &&
          other.anonymous == anonymous &&
          mapEquals(other.traits, traits));

  @override
  int get hashCode => Object.hash(id, name, anonymous, traits?.length);

  @override
  String toString() =>
      'ConfigDirectorContext(id: $id, name: $name, traits: $traits, anonymous: $anonymous)';
}

/// Metadata about your application. Including these values lets you write
/// targeting rules against them.
///
/// Each field the client is not given is filled in with the value the platform
/// reports for the running application, so most applications do not need to set
/// either one.
@immutable
final class ConfigDirectorMetaContext {
  const ConfigDirectorMetaContext({this.appName, this.appVersion});

  /// Your application's name. Defaults to the name the platform reports, such
  /// as the application label on Android or `CFBundleDisplayName` on iOS.
  final String? appName;

  /// Your application's version. Defaults to the version the platform reports,
  /// such as `versionName` on Android or `CFBundleShortVersionString` on iOS.
  final String? appVersion;

  /// The wire representation sent to the ConfigDirector server. Fields left
  /// unset are omitted rather than sent as `null`.
  Map<String, Object?> toJson() => {
    if (appName != null) 'appName': appName,
    if (appVersion != null) 'appVersion': appVersion,
  };
}

/// The application metadata together with the identifying details of this SDK.
@immutable
final class SdkMetaContext {
  const SdkMetaContext({
    required this.sdkName,
    required this.sdkVersion,
    this.metadata,
    this.userAgent,
  });

  final String sdkName;
  final String sdkVersion;
  final ConfigDirectorMetaContext? metadata;

  /// The browser's user agent on web, and the platform name elsewhere.
  final String? userAgent;

  /// Returns a copy of this context carrying [metadata] in place of its own.
  SdkMetaContext withMetadata(ConfigDirectorMetaContext metadata) =>
      SdkMetaContext(
        sdkName: sdkName,
        sdkVersion: sdkVersion,
        metadata: metadata,
        userAgent: userAgent,
      );

  Map<String, Object?> toJson() => {
    ...?metadata?.toJson(),
    'sdkName': sdkName,
    'sdkVersion': sdkVersion,
    if (userAgent != null) 'userAgent': userAgent,
  };
}

/// Why a config evaluated to the value it did.
enum EvaluationReason {
  /// The config state was found and its value matched the requested type.
  foundMatch('found-match'),

  /// No state was received for the config key.
  configStateMissing('config-state-missing'),

  /// The client had not received config state yet.
  clientNotReady('client-not-ready'),

  /// The config's type is incompatible with the requested type.
  typeMismatch('type-mismatch'),

  /// The config has no value for the current context.
  valueMissing('value-missing'),

  /// The config value could not be parsed as a number.
  invalidNumber('invalid-number'),

  /// The config value could not be parsed as JSON.
  invalidJson('invalid-json'),

  /// The config value could not be parsed as a boolean.
  invalidBoolean('invalid-boolean');

  const EvaluationReason(this.wireName);

  /// The name this reason is reported to the ConfigDirector server under.
  final String wireName;
}

/// The outcome of evaluating a single config.
@immutable
final class ConfigEvaluation {
  const ConfigEvaluation({
    required this.key,
    required this.value,
    required this.isDefaultValue,
    required this.reason,
    this.valueId,
    this.context,
  });

  /// The key of the config that was evaluated.
  final String key;

  /// The value the config evaluated to. This is the default value supplied by
  /// the caller when [isDefaultValue] is `true`.
  final Object value;

  /// Identifies the specific config value that was served, for telemetry. It is
  /// `null` when the default value was returned.
  final String? valueId;

  /// Whether the default value provided by the caller was returned.
  final bool isDefaultValue;

  /// Why the config evaluated to [value].
  final EvaluationReason reason;

  /// The context the config was evaluated against, if one was set.
  final ConfigDirectorContext? context;

  @override
  String toString() =>
      'ConfigEvaluation(key: $key, value: $value, isDefaultValue: $isDefaultValue, '
      'reason: ${reason.wireName})';
}

/// How the client connects to the ConfigDirector server.
enum ConnectionMode {
  /// Keeps a connection open and receives updates as soon as config state
  /// changes in the ConfigDirector dashboard.
  streaming,

  /// Fetches config state during initialization and then on a fixed interval.
  polling,

  /// Fetches config state during initialization and on context updates only.
  oneTime,
}
