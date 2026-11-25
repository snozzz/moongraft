#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "==> [1/4] Checking MoonBit Toolchain Version"
moon version --all

echo ""
echo "==> [2/4] Running Pure-MoonBit Cross-Backend Showcase (moon run cmd/demo)"
moon run cmd/demo

echo ""
echo "==> [3/4] Running MoonBit Script-Mode Minimal Demo (moon run demo.mbtx)"
moon run demo.mbtx

if command -v node >/dev/null 2>&1; then
  echo "==> [4/4] Running Git Merge Driver CLI on examples/moonbit_move_edit/"
  moon build --target js --release
  ./scripts/moongraft-cli.sh merge \
    examples/moonbit_move_edit/base.mbt \
    examples/moonbit_move_edit/ours.mbt \
    examples/moonbit_move_edit/theirs.mbt
fi

echo ""
echo "✓ MoonGraft minimal demo completed successfully!"
