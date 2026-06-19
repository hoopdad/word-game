#!/usr/bin/env bash
# scripts/check-msal-config.sh — Validates MSAL/Entra config consistency
# Compares: Entra app registration ↔ deployed JS bundle ↔ source code ↔ Dockerfile build args
# Catches: empty env vars, scope mismatches, redirect URI gaps, token version issues
set -euo pipefail

info()  { printf '  %-55s %s\n' "$1" "$2"; }
pass()  { info "$1" "✅"; }
fail()  { info "$1" "❌ $2"; FAILURES=$((FAILURES + 1)); }
warn()  { info "$1" "⚠️  $2"; WARNINGS=$((WARNINGS + 1)); }
section() { echo ""; echo "── $1 ──"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WEB_DIR="$ROOT_DIR/word-game-web"

# Configuration (from deploy script or override)
WEB_CLIENT_ID="${ENTRA_WEB_CLIENT_ID:-b4d29652-ff30-43ea-90f6-830cc340f866}"
API_CLIENT_ID="${ENTRA_API_CLIENT_ID:-16f3fd41-cddd-44fb-a149-14314e62f7a8}"
TENANT_ID="${AZURE_TENANT_ID:-d52a6857-5f44-4f8f-bcc8-420952d3225d}"
RG="${AZURE_RESOURCE_GROUP:-wordgame-dev-rg}"

FAILURES=0
WARNINGS=0

echo "╔══════════════════════════════════════════════════════════╗"
echo "║       MSAL / Entra Configuration Validator              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "  Web Client ID: $WEB_CLIENT_ID"
echo "  API Client ID: $API_CLIENT_ID"
echo "  Tenant ID:     $TENANT_ID"

# ──────────────────────────────────────────────
# 1. Source Code Checks
# ──────────────────────────────────────────────
section "Source Code (word-game-web)"

if [ -d "$WEB_DIR/src" ]; then
  # Check useAuth.ts uses popup not redirect for token fallback
  AUTH_FILE="$WEB_DIR/src/hooks/useAuth.ts"
  if [ -f "$AUTH_FILE" ]; then
    if grep -q 'acquireTokenRedirect' "$AUTH_FILE"; then
      fail "useAuth.ts token fallback" "Uses acquireTokenRedirect — causes infinite refresh loops. Use acquireTokenPopup."
    else
      pass "useAuth.ts uses acquireTokenPopup"
    fi

    # Check scope construction uses VITE_MSAL_API_CLIENT_ID
    if grep -q 'VITE_MSAL_API_CLIENT_ID' "$AUTH_FILE"; then
      pass "useAuth.ts uses VITE_MSAL_API_CLIENT_ID for scope"
    elif grep -q 'VITE_MSAL_SCOPE' "$AUTH_FILE"; then
      warn "useAuth.ts scope env var" "Uses VITE_MSAL_SCOPE — ensure Dockerfile has matching ARG"
    fi
  else
    warn "useAuth.ts" "File not found at $AUTH_FILE"
  fi

  # Check main.tsx redirectUri uses window.location.origin
  MAIN_FILE="$WEB_DIR/src/main.tsx"
  if [ -f "$MAIN_FILE" ]; then
    if grep -q 'window.location.origin' "$MAIN_FILE"; then
      pass "main.tsx redirectUri uses runtime origin"
    elif grep -q 'VITE_MSAL_REDIRECT_URI' "$MAIN_FILE"; then
      fail "main.tsx redirectUri" "Uses build-time VITE_MSAL_REDIRECT_URI — will be wrong in production"
    fi

    if grep -q 'msalInstance.initialize()' "$MAIN_FILE" || grep -q 'initialize().then' "$MAIN_FILE"; then
      pass "main.tsx awaits msalInstance.initialize()"
    else
      fail "main.tsx MSAL init" "Missing msalInstance.initialize() — MSAL v3 requires it before any API call"
    fi
  fi

  # Check Dockerfile has all required MSAL build args
  DOCKERFILE="$WEB_DIR/Dockerfile"
  if [ -f "$DOCKERFILE" ]; then
    REQUIRED_ARGS=("VITE_MSAL_CLIENT_ID" "VITE_MSAL_AUTHORITY" "VITE_MSAL_API_CLIENT_ID" "VITE_API_BASE_URL")
    for arg in "${REQUIRED_ARGS[@]}"; do
      if grep -q "ARG $arg" "$DOCKERFILE"; then
        pass "Dockerfile ARG $arg"
      else
        fail "Dockerfile" "Missing ARG $arg — won't be available at build time"
      fi
    done
  fi
else
  warn "Source code" "word-game-web/src not found at $WEB_DIR"
fi

# ──────────────────────────────────────────────
# 2. Entra App Registration Checks
# ──────────────────────────────────────────────
section "Entra App Registration"

if command -v az &>/dev/null && az account show &>/dev/null 2>&1; then
  # Web app registration
  WEB_APP=$(az ad app show --id "$WEB_CLIENT_ID" 2>/dev/null || echo "")
  if [ -n "$WEB_APP" ]; then
    # Check redirect URIs include the deployed WAF FQDN
    WAF_FQDN=$(az containerapp show --name word-game-waf --resource-group "$RG" \
      --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || echo "")
    if [ -n "$WAF_FQDN" ]; then
      REDIRECT_URIS=$(echo "$WEB_APP" | jq -r '.spa.redirectUris[]' 2>/dev/null || echo "")
      if echo "$REDIRECT_URIS" | grep -q "$WAF_FQDN"; then
        pass "Redirect URI includes deployed WAF FQDN"
      else
        fail "Redirect URI" "Missing https://$WAF_FQDN/* — add SPA redirect URI in Entra portal"
        echo "       Registered URIs:"
        echo "$REDIRECT_URIS" | sed 's/^/         /'
      fi
    fi

    # Check signInAudience
    AUDIENCE=$(echo "$WEB_APP" | jq -r '.signInAudience' 2>/dev/null || echo "")
    info "signInAudience" "$AUDIENCE"

    # Check isFallbackPublicClient
    IS_PUBLIC=$(echo "$WEB_APP" | jq -r '.isFallbackPublicClient' 2>/dev/null || echo "")
    if [ "$IS_PUBLIC" = "true" ]; then
      pass "isFallbackPublicClient = true (SPA)"
    else
      fail "isFallbackPublicClient" "Should be true for SPA public client"
    fi
  else
    fail "Web app registration" "Cannot find app $WEB_CLIENT_ID in Entra"
  fi

  # API app registration
  API_APP=$(az ad app show --id "$API_CLIENT_ID" 2>/dev/null || echo "")
  if [ -n "$API_APP" ]; then
    # Check the scope exists
    SCOPE_VALUE=$(echo "$API_APP" | jq -r '.api.oauth2PermissionScopes[]? | select(.value=="access_as_user") | .value' 2>/dev/null || echo "")
    if [ "$SCOPE_VALUE" = "access_as_user" ]; then
      pass "API exposes access_as_user scope"
    else
      fail "API scope" "Missing 'access_as_user' permission scope"
    fi

    # Check token version
    TOKEN_VER=$(echo "$API_APP" | jq -r '.api.requestedAccessTokenVersion // 1' 2>/dev/null || echo "")
    if [ "$TOKEN_VER" = "2" ]; then
      pass "API token version = v2"
    else
      warn "API token version" "= v$TOKEN_VER (v2 recommended for MSAL)"
    fi
  fi

  # Check consent grants
  WEB_SP_ID=$(az ad sp show --id "$WEB_CLIENT_ID" --query id -o tsv 2>/dev/null || echo "")
  if [ -n "$WEB_SP_ID" ]; then
    CONSENT=$(az rest --method GET \
      --url "https://graph.microsoft.com/v1.0/servicePrincipals/$WEB_SP_ID/oauth2PermissionGrants" \
      --query "value[?scope=='access_as_user'].consentType" -o tsv 2>/dev/null || echo "")
    if [ -n "$CONSENT" ]; then
      pass "Admin consent granted (type: $CONSENT)"
    else
      warn "Admin consent" "Not granted — users will see consent prompt on first login"
    fi
  fi
else
  warn "Entra checks" "az CLI not logged in — skipping Entra validation"
fi

# ──────────────────────────────────────────────
# 3. Deployed Bundle Checks
# ──────────────────────────────────────────────
section "Deployed Bundle"

WAF_FQDN="${WAF_FQDN:-$(az containerapp show --name word-game-waf --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || echo "")}"

if [ -n "$WAF_FQDN" ]; then
  BASE="https://$WAF_FQDN"
  BUNDLE_PATH=$(curl -s "$BASE/" 2>/dev/null | grep -oP 'src="/assets/index-[^"]+\.js"' | sed 's/src="//;s/"//' || echo "")

  if [ -n "$BUNDLE_PATH" ]; then
    BUNDLE=$(curl -s "$BASE$BUNDLE_PATH" 2>/dev/null)

    # Scope check
    BUNDLE_SCOPE=$(echo "$BUNDLE" | grep -oP 'api://[^"'"'"']+' | head -1 || echo "")
    if [ -z "$BUNDLE_SCOPE" ]; then
      fail "Bundle MSAL scope" "No api:// scope found"
    elif echo "$BUNDLE_SCOPE" | grep -qP '^api:///'; then
      fail "Bundle MSAL scope" "Empty client ID: '$BUNDLE_SCOPE' — VITE_MSAL_API_CLIENT_ID was empty at build time"
    elif [ "$BUNDLE_SCOPE" = "api://$API_CLIENT_ID/access_as_user" ]; then
      pass "Bundle scope = $BUNDLE_SCOPE"
    else
      warn "Bundle scope" "Unexpected: $BUNDLE_SCOPE (expected api://$API_CLIENT_ID/access_as_user)"
    fi

    # ClientId check
    BUNDLE_CLIENT=$(echo "$BUNDLE" | grep -oP "clientId:\"$WEB_CLIENT_ID\"" | head -1 || echo "")
    if [ -n "$BUNDLE_CLIENT" ]; then
      pass "Bundle clientId = $WEB_CLIENT_ID"
    else
      fail "Bundle clientId" "Expected $WEB_CLIENT_ID not found in bundle"
    fi

    # Authority check — accept either tenant-specific or /common
    EXPECTED_AUTH_TENANT="https://login.microsoftonline.com/$TENANT_ID"
    EXPECTED_AUTH_COMMON="https://login.microsoftonline.com/common"
    BUNDLE_AUTH=$(echo "$BUNDLE" | grep -oP 'authority:"[^"]+"' | head -1 || echo "")
    if echo "$BUNDLE_AUTH" | grep -qF "$EXPECTED_AUTH_TENANT"; then
      pass "Bundle authority = $EXPECTED_AUTH_TENANT"
    elif echo "$BUNDLE_AUTH" | grep -qF "$EXPECTED_AUTH_COMMON"; then
      pass "Bundle authority = $EXPECTED_AUTH_COMMON (multi-tenant/personal MSA)"
    elif [ -n "$BUNDLE_AUTH" ]; then
      warn "Bundle authority" "Found: $BUNDLE_AUTH (expected tenant or /common)"
    else
      fail "Bundle authority" "No authority config found in bundle"
    fi

    # API base URL check
    if echo "$BUNDLE" | grep -qP '"/api"'; then
      pass "Bundle API baseURL = /api"
    elif echo "$BUNDLE" | grep -q 'localhost'; then
      fail "Bundle API baseURL" "Contains localhost fallback — VITE_API_BASE_URL not set"
    fi
  else
    fail "Bundle detection" "Could not find JS bundle at $BASE"
  fi
else
  warn "Deployed bundle" "WAF FQDN not available — skipping bundle checks"
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: FAIL — $FAILURES error(s), $WARNINGS warning(s)"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "RESULT: PASS with $WARNINGS warning(s)"
  exit 0
else
  echo "RESULT: PASS — all MSAL/Entra checks passed"
  exit 0
fi
