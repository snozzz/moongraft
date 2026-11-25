#!/usr/bin/env bash
set -euo pipefail
REPO_NAME="${1:-moongraft}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated yet. Please run:"
  echo "  gh auth login"
  echo "Then re-run:"
  echo "  ./scripts/publish_github.sh $REPO_NAME"
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin main
else
  gh repo create "$REPO_NAME" \
    --public \
    --description "MoonGraft: Syntax-aware 3-way CST merge engine, move-edit refactoring resolver & multi-agent Git merge driver in pure MoonBit" \
    --source="$ROOT_DIR" \
    --remote=origin \
    --push
fi
