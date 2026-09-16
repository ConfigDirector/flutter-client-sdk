# ConfigDirector Flutter SDK

[![CI][ci-badge]][ci] [![pub.dev][pub-badge]][pub]

Flutter SDK for [ConfigDirector](https://www.configdirector.com), remote config and feature flags with typed values, JSON Schema validation, and safe renames of live flags. Start free, no card required.

## Install

```bash
flutter pub add configdirector_flutter_client_sdk
```

## Retrieve a value

```dart
import 'package:configdirector_flutter_client_sdk/configdirector_flutter_client_sdk.dart';

final client = ConfigDirectorClient(clientSdkKey: 'YOUR-CLIENT-SDK-KEY');
await client.initialize();

final darkMode = client.getValue('dark-mode', false);
```

Full details are in the [official documentation](https://docs.configdirector.com/sdks/mobile/flutter).

## Documentation

Refer to the [official documentation for the Flutter SDK](https://docs.configdirector.com/sdks/mobile/flutter).

There is also [a quickstart guide for ConfigDirector and any of our SDKs](https://docs.configdirector.com/getting-started/quickstart).

## Getting Help

- [Ask a question in Discussions](https://github.com/orgs/ConfigDirector/discussions)
- [Contact support](https://www.configdirector.com/support)

[//]: # "links"
[ci-badge]: https://github.com/ConfigDirector/flutter-client-sdk/actions/workflows/build.yml/badge.svg
[ci]: https://github.com/ConfigDirector/flutter-client-sdk/actions/workflows/build.yml
[pub-badge]: https://img.shields.io/pub/v/configdirector_flutter_client_sdk
[pub]: https://pub.dev/packages/configdirector_flutter_client_sdk
