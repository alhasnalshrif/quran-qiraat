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
  if [ "${UPDATE_INTEGRATION:-0}" = "1" ]; then
  echo "=== 4b. Live update loop against the deployed server ==="
  UPDATE_INTEGRATION=1 flutter test --no-pub test/integration/published_server_test.dart
fi

echo "=== 5. Node workspace lint, typecheck, build and tests ==="
  pnpm -r lint
  pnpm -r typecheck
  pnpm -r build
  pnpm -r test
fi

echo "=== All verification checks passed! ==="
