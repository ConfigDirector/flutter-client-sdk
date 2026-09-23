# Contributing

## Layout

This repository hosts every ConfigDirector Flutter and Dart package, one directory each under
[packages/](packages/). A package's directory is named after the package on pub.dev, and holds
everything that is published with it: its `pubspec.yaml`, `README.md`, `CHANGELOG.md`, `LICENSE`,
sources, tests and sample app.

| Package                                                                                             | What it is                                                            |
| --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| [configdirector_flutter_client_sdk](packages/configdirector_flutter_client_sdk)                     | The Flutter client SDK                                                |
| [configdirector_openfeature_flutter_provider](packages/configdirector_openfeature_flutter_provider) | OpenFeature provider wrapping the client SDK. Not released: see below |

The OpenFeature provider builds on `openfeature_dart_client_sdk`, the static-context client SDK,
which is in its first beta. Until that settles the provider is marked `publish_to: "none"` and is
left out of the root README. It depends on the client SDK in the working tree through a `path`
dependency, because it needs the SDK's unreleased `evaluate` and wrapper API; switch it to the
published version before the first release. It needs Dart 3.12.2, so Flutter 3.44.2 or later.

The provider reports itself to the server as `flutter-openfeature-client-provider`, at the
version in its `lib/src/constants.dart`, which `dart run tool/update_sdk_version.dart` keeps in
step with its pubspec the same way as the client SDK's.

What is shared sits at the root: the Flutter pin in [.fvmrc](.fvmrc), the
[validation](tool/validate.sh) and [format](format.sh) scripts, the git hooks and the workflows.
The packages are deliberately not a pub workspace. Workspaces need Dart 3.6, and the client SDK
supports Dart 3.4.

## Development

The Flutter version is pinned in [.fvmrc](.fvmrc), for CI and workstations alike, because
`dart format` output changes between SDK releases. Use [fvm](https://fvm.app) so your toolchain
matches:

```sh
fvm install
fvm use
cd packages/configdirector_flutter_client_sdk
fvm flutter pub get
```

Any Flutter from 3.22.0 up builds and tests the client SDK. Only formatting depends on the pin.

## Building and testing

```sh
./tool/validate.sh
```

Run from the repository root, that runs what the `build` workflow runs: the formatting check for
the whole repository, then for every package `pub get` for the package and its sample app,
`flutter analyze --fatal-infos`, the package tests on the Dart VM, the sample app's tests, and the
package tests in Chrome when a Chrome is found. Pass `--no-web` to skip the Chrome run and `--fix`
to format before checking.

Narrower loops while working, from a package's directory:

```sh
flutter test                                  # the package's tests
flutter test test/client_test.dart            # one file
flutter test --platform chrome                # the web build of the tests
flutter analyze --fatal-infos
../../format.sh                               # format the repository through the pinned SDK
```

The formatter is told `--language-version=latest` everywhere. The client SDK targets Dart 3.4 to
support Flutter 3.22, and left alone `dart format` would rewrite everything into the pre-3.7 short
style. Every invocation has to pass the same flag, which is why `format.sh` and `validate.sh` exist
rather than a bare `dart format .`.

The SDK compiles for both the Dart VM and the web, and the two disagree about numbers, platform
APIs and conditional imports. A change that touches any of those should be run under
`--platform chrome` as well as on the VM.

## Tests

A test is only worth having if it fails when the behavior it covers breaks. Write it before the
implementation and watch it fail for the right reason; if it was written afterwards, break the
implementation on purpose, confirm that test fails, then put the implementation back.

## The pre-push hook

Install it once per clone:

```sh
git config core.hooksPath tool/hooks
```

It runs `tool/validate.sh` against the working tree before every push. Bypass a single push with
`git push --no-verify`.

## CI

[build.yml](.github/workflows/build.yml) runs on every push and pull request: formatting for the
whole repository, then per package analysis and the sample app's tests on the pinned Flutter, the
package tests on the VM and in Chrome, and the package tests on the minimum Flutter the package
supports, 3.22.0 for the client SDK. That last job catches SDK-pinned dependency conflicts and
syntax that only a newer analyzer accepts, and it is the one thing `validate.sh` cannot reproduce
locally. A new package is added to each job's matrix.

## Sample app

[example/](packages/configdirector_flutter_client_sdk/example/) in the client SDK is a single-screen
app that pub.dev renders as the package's Example tab. It depends on the *published* SDK, the way a
consumer does, so it lags a release rather than tracking the working tree. See [its
README](packages/configdirector_flutter_client_sdk/example/README.md) for running it against your
own project.

## Releasing

Packages are released one at a time, each on its own version. Publishing is not reversible, so the
workflow checks the tag, the pubspec, `sdkVersion` and the changelog against each other before
uploading.

The steps below are for the client SDK, from [its
directory](packages/configdirector_flutter_client_sdk).

1. Bump `version` in [pubspec.yaml](packages/configdirector_flutter_client_sdk/pubspec.yaml).
2. Run `dart run tool/update_sdk_version.dart` to copy it into
   [lib/src/constants.dart](packages/configdirector_flutter_client_sdk/lib/src/constants.dart).
   `sdkVersion` is sent to the server with every telemetry batch, and `test/version_sync_test.dart`
   fails if the two drift.
3. Rename the `## [Unreleased]` heading in
   [CHANGELOG.md](packages/configdirector_flutter_client_sdk/CHANGELOG.md) to
   `## [X.Y.Z] - YYYY-MM-DD`, and start a fresh empty `## [Unreleased]` above it.
4. Commit, tag that commit `<package>-vX.Y.Z`, and push the tag:

   ```sh
   git tag configdirector_flutter_client_sdk-vX.Y.Z
   git push origin configdirector_flutter_client_sdk-vX.Y.Z
   ```

The tag names the package it releases, which is how one workflow serves every package, and the
package's automated publishing settings on pub.dev use the matching tag pattern,
`configdirector_flutter_client_sdk-v{{version}}`. Releases up to 1.1.0 were tagged `vX.Y.Z`,
before the repository held more than one package.

[publish.yml](.github/workflows/publish.yml) does the rest. It takes the package from the tag,
verifies the tag matches the pubspec version and `sdkVersion`, verifies the changelog has a heading
for the version, runs analysis and the tests, then publishes to pub.dev. Authentication uses
pub.dev's automated publishing: GitHub mints a short-lived OIDC token for the run and pub.dev
accepts it, so there is no secret to store or rotate. A version with a hyphen in it, tagged for
example `configdirector_flutter_client_sdk-v1.0.0-rc.1`, publishes as a prerelease.

Run the workflow by hand from the Actions tab to rehearse a release, naming the package. A manual
run does everything except the upload, ending in `flutter pub publish --dry-run`.

Once the version is live on pub.dev, bump the sample app's dependency in
[example/pubspec.yaml](packages/configdirector_flutter_client_sdk/example/pubspec.yaml). It
deliberately lags the SDK: naming a version that is not published yet leaves it unresolvable.
