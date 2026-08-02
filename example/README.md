# ConfigDirector Flutter sample app

A two-tab Flutter app showing how to use the ConfigDirector client SDK: one tab
reads configs and re-renders as they change, the other edits the context those
configs are evaluated against.

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

`env.json` is git-ignored. The key is read at build time through
`String.fromEnvironment`, so it never has to be committed — see
[lib/main.dart](lib/main.dart).

The Flags tab reads the keys of the ConfigDirector sample project
(`temporary-feature-flag`, `permanent-kill-switch`, `integer-config`,
`day-of-the-week-config`, `json-value-config`). Pointing the app at a project
without them is fine: each config falls back to the default value passed
alongside its key.

## What to look at

| File | What it shows |
| --- | --- |
| [lib/src/app.dart](lib/src/app.dart) | Creating, initializing and disposing a single client for the whole app |
| [lib/src/config_director_scope.dart](lib/src/config_director_scope.dart) | Handing that client to the widget tree with an `InheritedWidget` |
| [lib/src/config_value.dart](lib/src/config_value.dart) | Rebuilding on config changes with `watch` and a `StreamBuilder` |
| [lib/src/flags_screen.dart](lib/src/flags_screen.dart) | Reading `bool`, `int`, `String` and JSON configs, and the client's ready event |
| [lib/src/context_screen.dart](lib/src/context_screen.dart) | Re-evaluating every config against a new context with `updateContext` |

## Using the SDK in your own app

This app resolves the SDK from the repository it lives in:

```yaml
dependencies:
  configdirector_flutter_client_sdk: ^0.0.2

# Delete this once the package is published to pub.dev.
dependency_overrides:
  configdirector_flutter_client_sdk:
    path: ../
```

In your own app you only need the `dependencies` entry.

## Tests

```sh
flutter test
```

Both screens are tested against
[a stub client](test/support/fake_client.dart) rather than a real connection,
which is also how you would keep your own widget tests off the network.
