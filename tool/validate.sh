#!/usr/bin/env bash
#
# Runs the checks the `build` workflow runs, for every package under packages/,
# so a push does not have to wait on CI to find out. From the repository root:
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

packages=()
for pubspec in packages/*/pubspec.yaml; do
  [[ -f "$pubspec" ]] && packages+=("$(basename "$(dirname "$pubspec")")")
done

if [[ ${#packages[@]} -eq 0 ]]; then
  echo "No packages found under packages/." >&2
  exit 1
fi

# The `flutter` tool takes the package to work on from the working directory.
in_package() {
  local package="$1"
  shift
  (cd "packages/$package" && "$@")
}

in_example() {
  local package="$1"
  shift
  (cd "packages/$package/example" && "$@")
}

# The formatter picks its style from a package's language version, and the
# client SDK targets Dart 3.4 to support Flutter 3.22. Left alone, `dart format`
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

# `flutter test --platform chrome` needs a browser the Flutter tool can find.
web_skip_reason=""
if [[ $run_web -eq 0 ]]; then
  web_skip_reason="skipped via --no-web"
elif [[ -z "${CHROME_EXECUTABLE:-}" ]] &&
  ! command -v google-chrome >/dev/null 2>&1 &&
  ! command -v chromium >/dev/null 2>&1 &&
  [[ ! -d "/Applications/Google Chrome.app" ]]; then
  web_skip_reason="no Chrome found; set CHROME_EXECUTABLE"
fi

for package in "${packages[@]}"; do
  check "$package: pub get" in_package "$package" flutter pub get

  # A sample app under example/ is a package of its own, and `flutter analyze`
  # descends into it, so its dependencies have to be resolved as well or every
  # import in it reads as unresolved.
  if [[ -f "packages/$package/example/pubspec.yaml" ]]; then
    check "$package: pub get (example)" in_example "$package" flutter pub get
  fi

  check "$package: analyze" in_package "$package" flutter analyze --fatal-infos

  check "$package: test (vm)" in_package "$package" flutter test

  if [[ -d "packages/$package/example/test" ]]; then
    check "$package: test (example)" in_example "$package" flutter test
  fi

  if [[ -n "$web_skip_reason" ]]; then
    skipped+=("$package: test (chrome) -- $web_skip_reason")
  else
    check "$package: test (chrome)" in_package "$package" flutter test --platform chrome
  fi
done

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
