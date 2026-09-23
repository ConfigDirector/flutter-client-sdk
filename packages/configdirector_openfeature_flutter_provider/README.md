# ConfigDirector OpenFeature Provider for Flutter

[![CI][ci-badge]][ci] [![pub.dev][pub-badge]][pub]

[OpenFeature](https://openfeature.dev) provider for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with typed values, JSON Schema validation, and safe renames of live flags. Start free, no card required.

It plugs the [ConfigDirector Flutter SDK](https://pub.dev/packages/configdirector_flutter_client_sdk) into the [OpenFeature Dart client SDK](https://pub.dev/packages/openfeature_dart_client_sdk), the static-context SDK for client applications. It does not work with the OpenFeature Dart server SDK.

## Install

```bash
flutter pub add configdirector_openfeature_flutter_provider:^0.1.0-beta.1 openfeature_dart_client_sdk:^0.0.1-beta.1
```

The OpenFeature Dart client SDK is in beta, so the provider is published as a beta alongside it and both have to be asked for by version: pub never picks a pre-release on its own. Expect a new provider beta for each OpenFeature beta until they go stable together.

The OpenFeature Dart client SDK requires Dart 3.12.2, which ships with Flutter 3.44.2 and later.

## Retrieve a value

```dart
import 'package:configdirector_openfeature_flutter_provider/configdirector_openfeature_flutter_provider.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';

await OpenFeatureAPI.instance.setEvaluationContextAndWait(
  EvaluationContext(targetingKey: 'user-123'),
);
await OpenFeatureAPI.instance.setProviderAndWait(
  ConfigDirectorProvider(clientSdkKey: 'YOUR-CLIENT-SDK-KEY'),
);

final client = OpenFeatureAPI.instance.getClient();
final darkMode = client.getBooleanValue('dark-mode', false);
```

`setProviderAndWait` throws an `OpenFeatureException` when ConfigDirector cannot be reached in time. The provider keeps trying to connect and reports ready once it succeeds; until then flags resolve to their default values.

## Evaluation context

The OpenFeature evaluation context is sent to ConfigDirector as the user's context:

| OpenFeature                  | ConfigDirector |
| ---------------------------- | -------------- |
| `targetingKey`, or else `id` | `id`           |
| `name`                       | `name`         |
| `traits`, a structure        | `traits`       |
| `anonymous`, a boolean       | `anonymous`    |

Any other attribute is ignored. Put the values your targeting rules depend on inside `traits`. The context handed to an individual evaluation is ignored as well: flags are evaluated against the context most recently set.

```dart
await OpenFeatureAPI.instance.setEvaluationContextAndWait(
  EvaluationContext(
    targetingKey: 'user-123',
    attributes: {
      'name': 'Ada',
      'traits': {'plan': 'pro'},
    },
  ),
);
```

## Resolution details

A flag ConfigDirector served resolves with the reason `TARGETING_MATCH` and the served value's id as its variant. One the config has no value for resolves to the default with the reason `DEFAULT`. Everything else is an error carrying the default: `flagNotFound` for an unknown key, `providerNotReady` before config state has arrived, and `typeMismatch` for a value that cannot be read as the requested type.

```dart
final details = client.getBooleanDetails('dark-mode', false);
if (details.errorCode == ErrorCode.providerNotReady) {
  // Config state has not arrived yet.
}
```

## Documentation

Refer to the [official documentation for the OpenFeature Flutter provider](https://docs.configdirector.com/sdks/openfeature/flutter).

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/flutter-client-sdk/actions/workflows/build.yml/badge.svg
[ci]: https://github.com/ConfigDirector/flutter-client-sdk/actions/workflows/build.yml
[pub-badge]: https://img.shields.io/pub/v/configdirector_openfeature_flutter_provider
[pub]: https://pub.dev/packages/configdirector_openfeature_flutter_provider
