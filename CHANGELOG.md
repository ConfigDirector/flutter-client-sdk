# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The publish workflow refuses a tag whose version has no section in this file, so add the section
before tagging. See [Releasing](CONTRIBUTING.md#releasing).

## [Unreleased]

### Fixed

- A `watch` stream now falls back to its default when a full config update no longer carries its
  config. It used to keep yielding the last value it had seen while `getValue` already returned
  the default.

## [0.10.0] - 2026-08-13

### Changed

- Telemetry reports carry the SDK name and version, which the ConfigDirector dashboard uses to
  break down evaluations by SDK.
- The example app is a single file, so it reads in full on pub.dev.

## [0.1.0] - 2026-08-02

### Added

- `ConfigDirectorClient`, evaluating `bool`, `int`, `double`, `String` and JSON configs against a
  `ConfigDirectorContext`, with typed defaults.
- Streaming and polling transports, selectable through `ConnectionOptions`.
- `watch` streams and client events (`ClientReadyEvent`, `ConfigsUpdatedEvent`,
  `ContextUpdatedEvent`, `ConfigEvaluatedEvent`) for reacting to config and context changes.
- Telemetry reporting of evaluated configs, off the main isolate on native platforms.
- Support for both native and web targets.
