#!/usr/bin/env bash
# Phase 1 — run immediately after cloning the repo.
# Checks required tools, syncs any git submodules, and installs npm dependencies.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Tool check
# ---------------------------------------------------------------------------
REQUIRED_TOOLS=(git gh az terraform node npm jq)
MISSING=()

echo "[bootstrap-prereqs] checking required tools"
for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ✓ $tool"
  else
    echo "  ✗ $tool  (not found)"
    MISSING+=("$tool")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "[bootstrap-prereqs] missing required tools: ${MISSING[*]}"
  echo "  Install the missing tools and re-run this script."
  echo ""
  echo "  Quick install hints:"
  echo "    az        https://learn.microsoft.com/cli/azure/install-azure-cli"
  echo "    gh        https://cli.github.com"
  echo "    terraform https://developer.hashicorp.com/terraform/install"
  echo "    jq        https://stedolan.github.io/jq/download/"
  exit 1
fi

# ---------------------------------------------------------------------------
# Child repos (git submodules)
# ---------------------------------------------------------------------------
echo ""
echo "[bootstrap-prereqs] syncing child repos (git submodules)"
if [[ -f "$REPO_ROOT/.gitmodules" ]]; then
  git submodule update --init --recursive
  echo "  submodules synced"
else
  echo "  no .gitmodules found — skipping"
fi

# ---------------------------------------------------------------------------
# npm dependencies
# ---------------------------------------------------------------------------
echo ""
echo "[bootstrap-prereqs] installing npm dependencies"
npm install

# ---------------------------------------------------------------------------
# Next steps
# ---------------------------------------------------------------------------
echo ""
echo "[bootstrap-prereqs] done"
echo ""
echo "Next steps:"
echo "  1. Log in to Azure:  az login"
echo "  2. Select the target subscription:"
echo "       az account set --subscription <subscription-id>"
echo "  3. Log in to GitHub: gh auth login"
echo "  4. Run scripts/setup-oidc.sh to create the deployment identity"
echo "     and set GitHub OIDC secrets (do this before the first CD run)."
echo "  5. After infrastructure is deployed, run scripts/setup-github-vars.sh"
echo "     to set Entra / app-config GitHub variables."
