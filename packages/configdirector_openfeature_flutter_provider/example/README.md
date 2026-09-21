# ConfigDirector OpenFeature sample app

A single-screen Flutter app that reads ConfigDirector configs through
[OpenFeature](https://openfeature.dev), and re-renders as their values change.
It all lives in [lib/main.dart](lib/main.dart).

## Running it

1. The platform folders are not checked in. Generate the ones you need:

   ```sh
   flutter create --platforms=web,android,ios .
   ```

2. Copy the example environment file and fill in the client SDK key from your
   ConfigDirector dashboard:

   ```sh
   cp env.example.json env.json
   ```

3. Run the app on a device, a simulator, or Chrome:

   ```sh
   flutter run --dart-define-from-file=env.json
   ```

`env.json` is git-ignored. Alongside the key it can carry
`CONFIGDIRECTOR_USER_ID`, which becomes the OpenFeature `targetingKey` the
configs are evaluated against.

The app reads the keys of the ConfigDirector sample project
(`temporary-feature-flag`, `permanent-kill-switch`, `integer-config`,
`day-of-the-week-config`, `json-value-config`). Pointing the app at a project
without them is fine: each flag falls back to the default value passed alongside
its key.

## What to look at

| Part           | What it shows                                                                  |
| -------------- | ------------------------------------------------------------------------------ |
| `main`         | Creating the `ConfigDirectorProvider`                                          |
| `_register`    | Setting the evaluation context and registering the provider with OpenFeature   |
| `HomePage`     | Reading `bool`, `int`, `String` and structure flags with an OpenFeature client |
| `_rebuild`     | Rebuilding when the provider becomes ready or its configuration changes        |
