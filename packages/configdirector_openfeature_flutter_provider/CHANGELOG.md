# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-beta.8] - 2026-11-06

### Added

- The provider now implements OpenFeature's tracking. `client.track(name, details: details)` reports
  to ConfigDirector that something happened, such as a completed checkout, so ConfigDirector can show
  it on the live feed and count it for each variation of a running experiment. Before, a `track` call
  did nothing. The details' `value` is sent as the event's value and their attributes as the event's
  details. The event goes with the context the underlying client currently has, not the one handed to
  the call, as flag resolutions do.
- An event counts for an experiment only when that context has a `targetingKey` or `id`, the one the
  experiment's flag was resolved for. Without one, the event is still reported. The identifier of a
  context marked `anonymous` is not sent.
- Tracked events are sent with the next telemetry batch, at most 1,000 per batch; events beyond that
  are not reported. An event whose name does not have 1 to 150 characters is not reported. Attributes
  with more than 20 top-level keys or larger than 1 KB as JSON, and a `value` that is not a finite
  number, are left out and the event is still reported. Each of these logs one warning per telemetry
  batch. A `DateTime` attribute is sent as ISO 8601 text and a number that is not finite as `null`.
  `track` never throws, and does nothing in offline mode.

### Changed

- Requires version 1.8.0 of `configdirector_flutter_client_sdk`, which adds the variation to
  evaluations and `track`. Provider 0.1.0-beta.7 does not compile against that version, so an app on
  it that picked up the new SDK needs this provider to build again.
- The `variant` in evaluation details is now the variation's name when the config has variations
  and the variation served has a name, such as `treatment`. Before, it was always the value id. It
  stays the value id for a config without variations and for an unnamed variation. If you send
  `variant` to an analytics tool, an experiment's evaluations now show up under the variation names.
- The evaluation counts the provider sends to ConfigDirector now say which variation was served, and
  which percentage rollout and share served it, so ConfigDirector can count the contexts each
  variation of an experiment reached. This holds for values kept on the device as well.

### Fixed

- A telemetry report larger than ConfigDirector accepts is now discarded with a warning, and the next
  report is still sent. Before, the provider stopped sending telemetry until the app restarted.

## [0.1.0-beta.7] - 2026-11-01

### Changed

- Requires version 1.7.2 of `configdirector_flutter_client_sdk`, which fixes two issues. The values
  kept on the device no longer include the client SDK key, only its SHA-256 digest; values kept by
  an earlier version are removed on the first start after the upgrade, so that start resolves flags
  to their in-code default values until live values arrive. In polling mode, a context change now
  always gets the values for the new context: before, when no config had changed since the last
  values arrived, flags kept resolving against the previous context's values and the provider
  reported an error at the connection timeout. The configuration-changed event that follows a
  context change in polling mode now lists every flag.

## [0.1.0-beta.6] - 2026-10-23

### Added

- `ConnectionMode.offline` runs the provider without connecting to ConfigDirector, for example in
  a suite of UI tests that pins every flag to a known value. `ConnectionOptions.values` takes the
  values to serve, one per config key, and every evaluation context receives the same value with
  the reason `TARGETING_MATCH`; a flag without a value there resolves to its default with the
  `flagNotFound` error code. Registration completes at once with the provider ready, nothing is
  sent to ConfigDirector, and nothing is kept on the device. When the values cannot be loaded, for
  example a `null` value, `setProviderAndWait` throws the `ConfigDirectorInitializationException`
  the Flutter SDK throws, which the provider now exports, and the provider is not registered. See
  version 1.7.0 of `configdirector_flutter_client_sdk` for the values accepted.
- The provider serves the values the underlying client kept on the device from its last payload on
  the next launch of the same context, until live values arrive, so an app opened without a network
  resolves flags to the values ConfigDirector last sent instead of the default values passed to the
  OpenFeature client. Such a flag resolves with the reason `CACHED` and the value id as its variant.
  The provider reports `stale` when the kept values are loaded; `setProviderAndWait` still throws
  an `OpenFeatureException` when the connection times out, and the provider then reports `error`
  followed by `stale` again while it serves the kept values, and `ready` once live values arrive. A
  context change that cannot connect reports `reconciling`, `error` and `stale`. The `caching`
  field of `ConfigDirectorClientOptions` turns this off or replaces the store; `CachingOptions` and
  `CachingProvider` are exported from the provider. Requires version 1.7.0 of
  `configdirector_flutter_client_sdk`, which adds the values kept on the device.

### Changed

- `ConfigDirectorProvider` no longer requires `clientSdkKey`: it can be left out, or be empty, in
  offline mode. In `streaming` and `polling` mode a missing or blank key still throws a
  `ConfigDirectorValidationException` when the provider is created, so leaving it out there is now
  caught at that point instead of by the compiler.

## [0.1.0-beta.5] - 2026-10-15

### Added

- A top-level `kind` attribute of the evaluation context, beside `targetingKey`, is sent as the
  ConfigDirector context kind. It is read the way `id` is, so any value is sent as its text: `42`
  as `"42"` and `true` as `"true"`. Leaving it out means `user`, as before, and a `kind` inside
  `traits` stays an ordinary trait. Initializing or changing the context with an invalid context
  kind still succeeds and reports ready or a context change, never an error: the SDK logs an
  error, ignores the whole context, and flags resolve as if no context was set. Requires version
  1.6.0 of `configdirector_flutter_client_sdk`, which adds context kinds.

## [0.1.0-beta.4] - 2026-10-01

### Changed

- Configuration-changed events list the keys of configs that a full update removed after the keys
  the update carried, so flags backed by a removed config re-evaluate to their default values.
  Requires version 1.4.0 of `configdirector_flutter_client_sdk`.
- `ConnectionOptions.pollingInterval` defaults to 60 seconds and has a minimum of 30 seconds. In
  polling mode, a value below the minimum is raised to 30 seconds with a warning from the
  underlying `configdirector_flutter_client_sdk` client, which no longer throws for a zero or
  negative interval.
- Requires version 1.5.0 of `configdirector_flutter_client_sdk`.

## [0.1.0-beta.3] - 2026-09-26

### Changed

- Bumped the dependency to the latest `configdirector_flutter_client_sdk` which includes telemetry fixes

## [0.1.0-beta.2] - 2026-09-25

### Changed

- Bumped the dependency to the latest `configdirector_flutter_client_sdk` which includes evaluation type mismatch fixes

## [0.1.0-beta.1] - 2026-09-22

### Added

- `ConfigDirectorProvider`, an OpenFeature provider for the static-context Dart client SDK
  (`openfeature_dart_client_sdk`) backed by the ConfigDirector Flutter client SDK. A resolution
  carries the served value's id as its variant and `TARGETING_MATCH`, `DEFAULT` or an error code
  as its reason. The provider reports itself to the server as
  `flutter-openfeature-client-provider` at its own version.
