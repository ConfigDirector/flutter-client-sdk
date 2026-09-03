# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The publish workflow refuses a tag whose version has no section in this file, so add the section
before tagging. See [Releasing](CONTRIBUTING.md#releasing).

## [Unreleased]

### Fixed

- A streaming update whose fields have unexpected types is logged and skipped instead of
  surfacing as an uncaught `TypeError`. The same response from the polling endpoint is reported
  as a `ConfigDirectorConnectionError`.
- A server-sent `retry:` field too large for an integer is ignored instead of throwing.
- When `updateContext` is called again before the previous update has connected, the newer
  context wins: `context`, `onContextUpdated`, and telemetry attribution no longer end up on the
  older one. Resuming the network after a pause that interrupted `initialize` reconnects with the
  context that was passed to `initialize`.
- In polling mode, a context update issued while the previous fetch was still in flight no
  longer leaves a second poll running with the old context, and pausing the network during the
  initial fetch no longer starts polling once that fetch completes.
- Flushing telemetry twice in quick succession, which happens every time the app is
  backgrounded, no longer leaves an extra flush timer running for the life of the client.
- Pausing the network while the streaming connection was still being established no longer
  leaves that connection open in the background once the server answers.
- The time spent reading the app name and version from the platform no longer counts against
  the initialization timeout, so a slow platform channel on cold start no longer makes
  `initialize` give up on the first config set early.
- `isInitializing` returns to `false` once `initialize` completes, including when the connection
  failed or timed out. It used to stay `true` forever in those cases.
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
