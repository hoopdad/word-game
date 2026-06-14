#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "[verify-local] npm run lint"
npm run lint

echo "[verify-local] npm run test"
npm run test

echo "[verify-local] npm run build"
npm run build

echo "[verify-local] local verification passed"
