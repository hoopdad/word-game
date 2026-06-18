#!/usr/bin/env bash
# scripts/verify-deploy.sh — Post-deployment smoke test for all WAF→API→Web flows
# Run after azd-deploy.sh to verify routes, content types, and bundle correctness.
set -euo pipefail

info() { printf '  %-55s %s\n' "$1" "$2"; }
pass() { info "$1" "✅"; }
fail() { info "$1" "❌ $2"; FAILURES=$((FAILURES + 1)); }
warn() { info "$1" "⚠️  $2"; WARNINGS=$((WARNINGS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_OUTPUT_FILE="$HARNESS_DIR/.azure/tf-outputs.json"

RG="$(jq -er '.resource_group_name.value' "$TF_OUTPUT_FILE" 2>/dev/null || echo "")"

WAF_FQDN="${1:-$(az containerapp show --name word-game-waf --resource-group "${RG:-wordgame-dev-rg}" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || echo "")}"

[ -n "$WAF_FQDN" ] || { echo "ERROR: Cannot determine WAF FQDN. Pass it as argument or ensure deployment exists."; exit 1; }

BASE="https://${WAF_FQDN}"
FAILURES=0
WARNINGS=0

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           Post-Deploy Smoke Test                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "  Target: ${BASE}"
echo

# ──────────────────────────────────────────────
# 1. WAF Health
# ──────────────────────────────────────────────
echo "── WAF Health ──"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "GET /health → 200"
else
  fail "GET /health" "Expected 200, got $HTTP_CODE"
fi
echo

# ──────────────────────────────────────────────
# 2. SPA Routes (should serve index.html, 200)
# ──────────────────────────────────────────────
echo "── SPA Routes (user → WAF → web) ──"
for route in "/" "/register" "/dashboard" "/game"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE$route" 2>/dev/null || echo "000")
  CONTENT_TYPE=$(curl -s -I "$BASE$route" 2>/dev/null | grep -i "content-type:" | head -1 | tr -d '\r')
  if [ "$HTTP_CODE" = "200" ] && echo "$CONTENT_TYPE" | grep -qi "text/html"; then
    pass "GET ${route} → 200 (text/html)"
  else
    fail "GET ${route}" "Expected 200+html, got ${HTTP_CODE} ${CONTENT_TYPE}"
  fi
done
echo

# ──────────────────────────────────────────────
# 3. API Routes (should return 401 JSON, not 405/404/200-html)
# ──────────────────────────────────────────────
echo "── API Routes (user → WAF → api, expect 401 JSON) ──"

check_api_route() {
  local method="$1" path="$2"
  local curl_args=(-s -w "\n%{http_code}" -H "Content-Type: application/json")

  if [ "$method" = "POST" ]; then
    curl_args+=(-X POST -d '{}')
  elif [ "$method" = "PUT" ]; then
    curl_args+=(-X PUT -d '{}')
  fi

  local response
  response=$(curl "${curl_args[@]}" "$BASE$path" 2>/dev/null || echo -e "\n000")
  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" = "401" ]; then
    # Verify it's JSON, not HTML
    if echo "$body" | grep -q '"detail"'; then
      pass "${method} ${path} → 401 (JSON)"
    else
      fail "${method} ${path}" "Got 401 but response is not JSON API error"
    fi
  elif [ "$http_code" = "405" ]; then
    fail "${method} ${path}" "405 Method Not Allowed — route not reaching API backend"
  elif [ "$http_code" = "200" ] && echo "$body" | grep -q '<!doctype'; then
    fail "${method} ${path}" "200 with HTML — hitting web SPA fallback, not API"
  elif [ "$http_code" = "403" ]; then
    warn "${method} ${path}" "403 — WAF ModSecurity rule triggered (route works, payload blocked)"
  else
    fail "${method} ${path}" "Expected 401, got ${http_code}"
  fi
}

check_api_route GET  "/api/users/check-name/smoketest"
check_api_route POST "/api/users/register"
check_api_route GET  "/api/users/active"
check_api_route GET  "/api/game/status"
check_api_route POST "/api/game/start"
check_api_route GET  "/api/scores/all-time"
check_api_route GET  "/api/scores/today"
check_api_route GET  "/api/scores/game-count"
check_api_route GET  "/api/categories/config"
check_api_route PUT  "/api/categories/config"
check_api_route POST "/api/auth/ws-ticket"
echo

# ──────────────────────────────────────────────
# 4. CORS Preflight
# ──────────────────────────────────────────────
echo "── CORS Preflight ──"
PREFLIGHT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS \
  -H "Origin: $BASE" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Authorization, Content-Type" \
  "$BASE/api/users/register" 2>/dev/null || echo "000")
if [ "$PREFLIGHT_CODE" = "204" ]; then
  pass "OPTIONS /api/users/register → 204"
else
  fail "OPTIONS /api/users/register" "Expected 204, got $PREFLIGHT_CODE"
fi
echo

# ──────────────────────────────────────────────
# 5. JS Bundle Validation
# ──────────────────────────────────────────────
echo "── JS Bundle Validation ──"
BUNDLE_PATH=$(curl -s "$BASE/" 2>/dev/null | grep -oP 'src="/assets/index-[^"]+\.js"' | sed 's/src="//;s/"//' || echo "")
if [ -z "$BUNDLE_PATH" ]; then
  fail "Bundle detection" "Could not find JS bundle in index.html"
else
  BUNDLE_CONTENT=$(curl -s "$BASE$BUNDLE_PATH" 2>/dev/null)

  # Check API base URL is /api (not full URL or localhost)
  API_BASE=$(echo "$BUNDLE_CONTENT" | grep -oP 'new \w+\("([^"]+)"\)' | grep -oP '"[^"]*"' | head -1 || echo "")
  if echo "$API_BASE" | grep -q '"/api"'; then
    pass "Bundle baseURL = /api"
  elif echo "$API_BASE" | grep -q 'localhost'; then
    fail "Bundle baseURL" "Contains localhost — VITE_API_BASE_URL not set during build"
  elif echo "$API_BASE" | grep -q 'http'; then
    fail "Bundle baseURL" "Contains absolute URL — should be relative /api"
  else
    # Try alternative detection
    if echo "$BUNDLE_CONTENT" | grep -oP '"\K/api(?=")' | head -1 | grep -q '/api'; then
      pass "Bundle baseURL = /api (alt detection)"
    else
      fail "Bundle baseURL" "Could not verify — manual check needed"
    fi
  fi

  # Check payload field names (no camelCase in POST bodies)
  if echo "$BUNDLE_CONTENT" | grep -q '{displayName:'; then
    fail "Bundle payload" "Contains camelCase 'displayName' — API expects 'display_name'"
  elif echo "$BUNDLE_CONTENT" | grep -q '{display_name:'; then
    pass "Bundle register payload uses snake_case"
  fi

  # Check MSAL redirect uses runtime origin
  if echo "$BUNDLE_CONTENT" | grep -q 'window.location.origin'; then
    pass "MSAL redirectUri uses runtime origin"
  elif echo "$BUNDLE_CONTENT" | grep -q 'VITE_MSAL_REDIRECT_URI'; then
    fail "MSAL redirectUri" "Uses build-time env var — may be wrong in production"
  fi

  # Check MSAL scope has real API client ID (not empty api:///access_as_user)
  MSAL_SCOPE=$(echo "$BUNDLE_CONTENT" | grep -oP 'api://[^"]+' | head -1 || echo "")
  if [ -z "$MSAL_SCOPE" ]; then
    fail "MSAL scope" "No api:// scope found in bundle"
  elif echo "$MSAL_SCOPE" | grep -qP 'api:///'; then
    fail "MSAL scope" "Empty client ID: '$MSAL_SCOPE' — VITE_MSAL_API_CLIENT_ID not set at build time"
  elif echo "$MSAL_SCOPE" | grep -qP 'api://[0-9a-f-]+/access_as_user'; then
    pass "MSAL scope = $MSAL_SCOPE"
  else
    warn "MSAL scope" "Unexpected format: $MSAL_SCOPE"
  fi

  # Check MSAL clientId is set (not empty string)
  MSAL_CLIENT=$(echo "$BUNDLE_CONTENT" | grep -oP 'clientId:"[^"]*"' | grep -v 'clientId:""' | head -1 || echo "")
  if [ -n "$MSAL_CLIENT" ]; then
    pass "MSAL clientId is set"
  else
    fail "MSAL clientId" "Empty — VITE_MSAL_CLIENT_ID not set at build time"
  fi

  # Check no acquireTokenRedirect in app code (causes infinite loops)
  REDIRECT_COUNT=$(echo "$BUNDLE_CONTENT" | grep -oP 'acquireTokenRedirect\(' | wc -l)
  POPUP_COUNT=$(echo "$BUNDLE_CONTENT" | grep -oP 'acquireTokenPopup\(' | wc -l)
  if [ "$REDIRECT_COUNT" -gt 0 ] && [ "$POPUP_COUNT" -eq 0 ]; then
    fail "MSAL token fallback" "Uses acquireTokenRedirect without popup — may cause infinite refresh loops"
  else
    pass "MSAL token fallback uses popup (no redirect loops)"
  fi

  # Check WS URL uses runtime derivation
  if echo "$BUNDLE_CONTENT" | grep -q 'window.location.host'; then
    pass "WebSocket URL uses runtime derivation"
  fi
fi
echo

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════"
if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: FAIL — ${FAILURES} error(s), ${WARNINGS} warning(s)"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "RESULT: PASS with ${WARNINGS} warning(s)"
  exit 0
else
  echo "RESULT: PASS — all smoke tests passed"
  exit 0
fi
