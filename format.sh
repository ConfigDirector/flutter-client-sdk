#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# CI formats with the SDK pinned in .fvmrc. Go through fvm so this matches;
# without it, warn rather than silently reformatting to a different style.
if command -v fvm >/dev/null 2>&1; then
  exec fvm dart format --language-version=latest .
fi

pinned="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)"
current="$(flutter --version | sed -n '1s/^Flutter \([^ ]*\).*/\1/p')"

if [ "$pinned" != "$current" ]; then
  echo "warning: Flutter $current, but .fvmrc pins $pinned." >&2
  echo "warning: formatting may not match CI. Install fvm and run 'fvm use'." >&2
fi

dart format --language-version=latest .
