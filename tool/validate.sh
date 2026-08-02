#!/usr/bin/env bash
#
# Runs the checks the `build` workflow runs, so a push does not have to wait on
# CI to find out. From the package root:
#
#   ./tool/validate.sh            # everything
#   ./tool/validate.sh --fix      # apply formatting first, then check
#   ./tool/validate.sh --no-web   # skip the Chrome run
#
# The editor's formatter is switched off for this package (see
# .vscode/settings.json), so --fix is how you format.
#
# Every check runs even after an earlier one fails, so a single pass reports
# everything that needs fixing. Exits non-zero if any check failed.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

run_web=1
apply_fixes=0
for arg in "$@"; do
  case "$arg" in
    --no-web) run_web=0 ;;
    --fix) apply_fixes=1 ;;
    -h | --help)
      sed -n '2,15p' "$0" | cut -c 3-
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64
      ;;
  esac
done

failed=()
skipped=()

# Runs a command, printing a banner and recording the outcome.
check() {
  local name="$1"
  shift

  printf '\n\033[1m==> %s\033[0m\n' "$name"
  if "$@"; then
    return 0
  fi

  failed+=("$name")
  return 1
}

check "pub get" flutter pub get

# The sample app under example/ is a package of its own, and `flutter analyze`
# descends into it, so its dependencies have to be resolved as well or every
# import in it reads as unresolved.
check "pub get (example)" flutter pub get --directory example

# The formatter picks its style from the package's language version, and this
# package targets Dart 3.4 to support Flutter 3.22. Left alone, `dart format`
# would rewrite the whole repository into the pre-3.7 short style. Pinning the
# language version keeps the tall style without raising the SDK floor; it
# affects layout only, never which syntax is legal. Every invocation below must
# pass the same pin, or the two disagree about what "formatted" means.
if [[ $apply_fixes -eq 1 ]]; then
  check "format (--fix)" dart format --language-version=latest .
else
  check "format" dart format \
    --output=none \
    --set-exit-if-changed \
    --language-version=latest \
    . ||
    echo 'Fix with: ./tool/validate.sh --fix'
fi

check "analyze" flutter analyze --fatal-infos

check "test (vm)" flutter test

# The `flutter` tool takes the package to test from the working directory, so
# the sample app's tests have to be run from inside it.
example_tests() { (cd example && flutter test); }
check "test (example)" example_tests

# `flutter test --platform chrome` needs a browser the Flutter tool can find.
if [[ $run_web -eq 0 ]]; then
  skipped+=("test (chrome) -- skipped via --no-web")
elif [[ -n "${CHROME_EXECUTABLE:-}" ]] ||
  command -v google-chrome >/dev/null 2>&1 ||
  command -v chromium >/dev/null 2>&1 ||
  [[ -d "/Applications/Google Chrome.app" ]]; then
  check "test (chrome)" flutter test --platform chrome
else
  skipped+=("test (chrome) -- no Chrome found; set CHROME_EXECUTABLE")
fi

printf '\n'
for entry in "${skipped[@]:-}"; do
  [[ -n "$entry" ]] && printf '\033[33mSKIPPED\033[0m %s\n' "$entry"
done

if [[ ${#failed[@]} -gt 0 ]]; then
  printf '\033[31mFAILED\033[0m %s\n' "${failed[@]}"
  exit 1
fi

printf '\033[32mAll checks passed.\033[0m\n'
# CI additionally runs the suite against the oldest supported toolchain
# (Flutter 3.22.0), which catches SDK-pinned dependency conflicts and source
# that only a newer scanner accepts. This script cannot: it uses whichever
# Flutter is on your PATH.
printf 'Note: CI also runs the tests on Flutter 3.22.0, the minimum supported version.\n'
