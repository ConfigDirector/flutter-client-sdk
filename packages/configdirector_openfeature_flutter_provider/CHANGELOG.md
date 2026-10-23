# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-beta.6] - 2026-10-23

### Added

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
