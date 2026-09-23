# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ConfigDirectorProvider`, an OpenFeature provider for the static-context Dart client SDK
  (`openfeature_dart_client_sdk`) backed by the ConfigDirector Flutter client SDK. A resolution
  carries the served value's id as its variant and `TARGETING_MATCH`, `DEFAULT` or an error code
  as its reason. The provider reports itself to the server as
  `flutter-openfeature-client-provider` at its own version.
