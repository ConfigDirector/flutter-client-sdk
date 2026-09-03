# Contributing

## Development

The Flutter version is pinned in [.fvmrc](.fvmrc), for CI and workstations alike, because
`dart format` output changes between SDK releases. Use [fvm](https://fvm.app) so your toolchain
matches:

```sh
fvm install
fvm use
fvm flutter pub get
```

Any Flutter from 3.22.0 up builds and tests the package. Only formatting depends on the pin.

## Building and testing

```sh
./tool/validate.sh
```

That runs what the `build` workflow runs: `pub get` for the package and the sample app,
the formatting check, `flutter analyze --fatal-infos`, the package tests on the Dart VM, the sample
app's tests, and the package tests in Chrome when a Chrome is found. Pass `--no-web` to skip the
Chrome run and `--fix` to format before checking.

Narrower loops while working:

```sh
flutter test                                  # the package's tests
flutter test test/client_test.dart            # one file
flutter test --platform chrome                # the web build of the tests
flutter analyze --fatal-infos
./format.sh                                   # format through the pinned SDK
```

The formatter is told `--language-version=latest` everywhere. The package targets Dart 3.4 to
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

[build.yml](.github/workflows/build.yml) runs on every push and pull request: formatting, analysis
and the sample app's tests on the pinned Flutter, the package tests on the VM and in Chrome, and the
package tests on Flutter 3.22.0, the minimum supported version. That last job catches SDK-pinned
dependency conflicts and syntax that only a newer analyzer accepts, and it is the one thing
`validate.sh` cannot reproduce locally.

## Sample app

[example/](example/) is a single-screen app that pub.dev renders as the package's Example tab. It
depends on the *published* SDK, the way a consumer does, so it lags a release rather than tracking
the working tree. See [its README](example/README.md) for running it against your own project.

## Releasing

Publishing is not reversible, so the workflow checks the tag, the pubspec, `sdkVersion` and the
changelog against each other before uploading.

1. Bump `version` in [pubspec.yaml](pubspec.yaml).
2. Run `dart run tool/update_sdk_version.dart` to copy it into
   [lib/src/constants.dart](lib/src/constants.dart). `sdkVersion` is sent to the server with every
   telemetry batch, and `test/version_sync_test.dart` fails if the two drift.
3. Rename the `## [Unreleased]` heading in [CHANGELOG.md](CHANGELOG.md) to
   `## [X.Y.Z] - YYYY-MM-DD`, and start a fresh empty `## [Unreleased]` above it.
4. Commit, tag that commit `vX.Y.Z`, and push the tag:

   ```sh
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```

[publish.yml](.github/workflows/publish.yml) does the rest. It verifies the tag matches the pubspec
version and `sdkVersion`, verifies the changelog has a heading for the version, runs analysis and
the tests, then publishes to pub.dev. Authentication uses pub.dev's automated publishing: GitHub
mints a short-lived OIDC token for the run and pub.dev accepts it, so there is no secret to store or
rotate. A tag with a hyphen in it, such as `v1.0.0-rc.1`, publishes as a prerelease.

Run the workflow by hand from the Actions tab to rehearse a release. A manual run does everything
except the upload, ending in `flutter pub publish --dry-run`.

Once the version is live on pub.dev, bump the sample app's dependency in
[example/pubspec.yaml](example/pubspec.yaml). It deliberately lags the SDK: naming a version that is
not published yet leaves it unresolvable.
