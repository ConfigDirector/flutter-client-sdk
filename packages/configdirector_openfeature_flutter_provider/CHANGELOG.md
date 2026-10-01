# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
