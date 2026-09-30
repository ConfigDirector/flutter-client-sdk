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

## Test your code

`package:configdirector_flutter_client_sdk/testing.dart` creates a real client connected to an
in-memory server that your test controls, so the code under test runs against the production client
without opening a network connection, sending telemetry, or touching a platform channel. It ships in
the package and runs under `flutter test` on the VM and in a browser.

```dart
import 'package:configdirector_flutter_client_sdk/testing.dart';

final testClient = createTestClient(values: {'new-checkout': true});
addTearDown(testClient.client.dispose);
await testClient.client.initialize();

expect(testClient.client.getValue('new-checkout', false), isTrue);

testClient.setValue('new-checkout', false);
await pumpEventQueue();
expect(testClient.client.getValue('new-checkout', true), isFalse);
```

The test client also holds or fails `initialize` and `updateContext` (`holdInitialization`,
`completeInitialization`, `failInitialization`, and their `ContextUpdate` counterparts) so loading
and error states can be tested, and records every context in `contextUpdates`. Values keep their
type: a `bool`, an `int`, a `double`, a `String`, or a `Map` or `List` (a JSON config), and reads
behave exactly as they do against ConfigDirector. Updates arrive asynchronously: `await
pumpEventQueue()` in a `test`, `await tester.pumpAndSettle()` in a `testWidgets`. See [Test your
code](https://docs.configdirector.com/sdks/mobile/flutter#test-your-code) in the documentation for
the details.

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
