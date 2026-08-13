# Changelog

## 0.10.0

Update telemetry contract to support new ConfigDirector dashboard features.

- Telemetry now sends metadata about the SDK which is used in dashboard reports.
- Simplified the example app and inlined it in one file to be more easily viewable
  in pub.dev

## 0.1.0

Initial release of the ConfigDirector Flutter client SDK.

- `ConfigDirectorClient` for evaluating `bool`, `int`, `double`, `String` and
  JSON configs against a `ConfigDirectorContext`, with typed defaults.
- Streaming and polling transports, selectable through `ConnectionOptions`.
- `watch` streams and client events (`ClientReadyEvent`, `ConfigsUpdatedEvent`,
  `ContextUpdatedEvent`, `ConfigEvaluatedEvent`) for reacting to config and
  context changes.
- Telemetry reporting of evaluated configs, off the main isolate on native
  platforms.
- Support for both native and web targets.
