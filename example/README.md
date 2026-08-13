# ConfigDirector Flutter sample app

A single-screen Flutter app showing how to use the ConfigDirector client SDK: it
reads a handful of configs and re-renders as their values change.

It all lives in [lib/main.dart](lib/main.dart), which is also the only file
pub.dev shows on the package's
[Example tab](https://pub.dev/packages/configdirector_flutter_client_sdk/example).

## Running it

1. Copy the example environment file and fill in the client SDK key from your
   ConfigDirector dashboard:

   ```sh
   cp env.example.json env.json
   ```

2. Run the app on a device, a simulator, or Chrome:

   ```sh
   flutter run --dart-define-from-file=env.json
   ```

`env.json` is git-ignored. Everything in it is read at build time through
`String.fromEnvironment`, so nothing has to be committed — see
[lib/main.dart](lib/main.dart).

Alongside the key, `env.json` can carry the context the configs are evaluated
against: `CONFIGDIRECTOR_USER_ID`, `CONFIGDIRECTOR_USER_NAME` and
`CONFIGDIRECTOR_USER_ROLE` (sent as the `role` trait). Leave them empty and the
configs are evaluated without a context; change them and re-run to see targeting
rules take effect.

The app reads the keys of the ConfigDirector sample project
(`temporary-feature-flag`, `permanent-kill-switch`, `integer-config`,
`day-of-the-week-config`, `json-value-config`). Pointing the app at a project
without them is fine: each config falls back to the default value passed
alongside its key.

## What to look at

Reading [lib/main.dart](lib/main.dart) top to bottom, in order:

| Part                       | What it shows                                                          |
| -------------------------- | ---------------------------------------------------------------------- |
| `SampleApp`                | Creating, initializing and disposing a single client for the whole app |
| `_contextFromEnvironment`  | Passing a targeting context to `initialize`                            |
| `ConfigDirectorScope`      | Handing that client to the widget tree with an `InheritedWidget`       |
| `ConfigValue`              | Rebuilding on config changes with `watch` and a `StreamBuilder`        |
| `HomePage`                 | Reading `bool`, `int`, `String` and JSON configs                       |
| `_ReadyIndicator`          | Following the connection with the client's ready event                 |

## Using the SDK in your own app

```yaml
dependencies:
  configdirector_flutter_client_sdk: ^0.1.0
```

## Tests

```sh
flutter test
```

The screen is tested against [a stub client](test/support/fake_client.dart)
rather than a real connection, which is also how you would keep your own widget
tests off the network.
