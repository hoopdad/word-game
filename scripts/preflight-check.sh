#!/usr/bin/env bash
# scripts/preflight-check.sh — Pre-deployment validation gate
# Run BEFORE any azd provision / azd-deploy.sh to catch issues early.
# Usage: ./scripts/preflight-check.sh
set -euo pipefail

info() { printf '  %-55s %s\n' "$1" "$2"; }
pass() { info "$1" "✅"; PASSES=$((PASSES + 1)); }
fail() { info "$1" "❌ $2"; FAILURES=$((FAILURES + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$(cd "$HARNESS_DIR/../word-game-infra" && pwd 2>/dev/null || echo "")"

FAILURES=0
PASSES=0

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           Pre-Flight Deployment Checks                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo

# ──────────────────────────────────────────────
# 1. Terraform format check
# ──────────────────────────────────────────────
echo "── 1. Terraform Format ──"
if [ -n "$INFRA_DIR" ] && [ -d "$INFRA_DIR" ]; then
  if terraform -chdir="$INFRA_DIR" fmt -check -recursive >/dev/null 2>&1; then
    pass "terraform fmt -check"
  else
    fail "terraform fmt -check" "Run 'terraform fmt -recursive' in word-game-infra"
  fi
else
  fail "Infra directory" "Not found at $HARNESS_DIR/../word-game-infra"
fi
echo

# ──────────────────────────────────────────────
# 2. Terraform validate
# ──────────────────────────────────────────────
echo "── 2. Terraform Validate ──"
if [ -n "$INFRA_DIR" ] && [ -d "$INFRA_DIR" ]; then
  VALIDATE_OUT=$(terraform -chdir="$INFRA_DIR" validate -json 2>/dev/null || echo '{"valid":false}')
  if echo "$VALIDATE_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('valid') else 1)" 2>/dev/null; then
    pass "terraform validate"
  else
    ERROR_MSG=$(echo "$VALIDATE_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('diagnostics',[]); print(errs[0].get('summary','Unknown') if errs else 'Unknown')" 2>/dev/null || echo "Unknown")
    fail "terraform validate" "$ERROR_MSG"
  fi
else
  fail "Infra directory" "Not found"
fi
echo

# ──────────────────────────────────────────────
# 3. MSAL Config consistency
# ──────────────────────────────────────────────
echo "── 3. MSAL Configuration ──"
if [ -x "$HARNESS_DIR/scripts/check-msal-config.sh" ]; then
  if "$HARNESS_DIR/scripts/check-msal-config.sh" >/dev/null 2>&1; then
    pass "MSAL config check"
  else
    fail "MSAL config check" "Run scripts/check-msal-config.sh for details"
  fi
else
  pass "MSAL config check (script not found, skipped)"
fi
echo

# ──────────────────────────────────────────────
# 4. Contract compliance
# ──────────────────────────────────────────────
echo "── 4. Route/Contract Alignment ──"
if [ -x "$HARNESS_DIR/scripts/audit-routes.sh" ]; then
  if "$HARNESS_DIR/scripts/audit-routes.sh" >/dev/null 2>&1; then
    pass "Route audit"
  else
    fail "Route audit" "Run scripts/audit-routes.sh for details"
  fi
else
  pass "Route audit (script not found, skipped)"
fi
echo

# ──────────────────────────────────────────────
# 5. Azure CLI login check
# ──────────────────────────────────────────────
echo "── 5. Azure CLI ──"
if az account show --query "{sub:name,id:id}" -o tsv >/dev/null 2>&1; then
  SUB_NAME=$(az account show --query name -o tsv 2>/dev/null)
  pass "az login active ($SUB_NAME)"
else
  fail "az login" "Not logged in — run 'az login'"
fi
echo

# ──────────────────────────────────────────────
# 6. ACR accessibility
# ──────────────────────────────────────────────
echo "── 6. ACR Accessibility ──"
if az acr show --name wordgamedevacr --query "{loginServer:loginServer}" -o tsv >/dev/null 2>&1; then
  pass "ACR wordgamedevacr reachable"
else
  fail "ACR" "Cannot reach wordgamedevacr — check ACR public access"
fi
echo

# ──────────────────────────────────────────────
# 7. Container Apps environment health
# ──────────────────────────────────────────────
echo "── 7. Container Apps Environment ──"
ENV_STATE=$(az containerapp env show --name wordgame-dev-cae-edge --resource-group wordgame-dev-rg \
  --query properties.provisioningState -o tsv 2>/dev/null || echo "NotFound")
if [ "$ENV_STATE" = "Succeeded" ]; then
  pass "CAE edge provisioning: $ENV_STATE"
else
  fail "CAE edge" "State: $ENV_STATE (expected Succeeded)"
fi
echo

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════"
echo "  Results: ${PASSES} passed, ${FAILURES} failed"
echo "══════════════════════════════════════════════════════════"

if [ "$FAILURES" -gt 0 ]; then
  echo "  ❌ PRE-FLIGHT FAILED — do NOT deploy"
  exit 1
else
  echo "  ✅ PRE-FLIGHT PASSED — safe to deploy"
  exit 0
fi
