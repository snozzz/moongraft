#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JS_ENTRY="$ROOT_DIR/_build/js/release/build/cmd/main/main.js"

if [ ! -f "$JS_ENTRY" ]; then
  moon -C "$ROOT_DIR" build --target js --release >/dev/null
fi

exec node "$JS_ENTRY" "$@"
