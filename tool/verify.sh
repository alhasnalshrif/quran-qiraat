#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== 1. Flutter analyze ==="
flutter analyze --no-pub

echo "=== 2. Flutter test ==="
flutter test --no-pub

echo "=== 3. Check Mushaf layout ==="
node tool/import_mushaf_layout.mjs --check

echo "=== 4. Check Qiraat variants ==="
python3 tool/import_qiraat_variants.py --check

if [ -f "pnpm-workspace.yaml" ]; then
  echo "=== 5. Server/Admin checks ==="
  pnpm -r lint
  pnpm -r test
fi

echo "=== All verification checks passed! ==="
