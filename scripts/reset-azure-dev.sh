#!/usr/bin/env bash
# Destructive dev reset helper.
# Deletes the live dev resource group so the stack can be recreated by the
# existing CI/CD pipeline after the Terraform changes land on main.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RG_NAME="${RG_NAME:-rg-wordgame-dev}"

if [[ "${1:-}" != "--yes" ]]; then
  echo "[reset-azure-dev] Refusing to delete $RG_NAME without --yes"
  echo "Usage: $0 --yes"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "[reset-azure-dev] ERROR: run 'az login' first" >&2
  exit 1
fi

echo "[reset-azure-dev] deleting resource group $RG_NAME"
az group delete --name "$RG_NAME" --yes --no-wait

echo "[reset-azure-dev] waiting for deletion to finish"
az group wait --name "$RG_NAME" --deleted

echo "[reset-azure-dev] done"
echo "Next step: merge the PR and let the existing CD workflow recreate the stack."
