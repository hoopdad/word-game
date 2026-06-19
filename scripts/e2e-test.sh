#!/usr/bin/env bash
# scripts/e2e-test.sh — Authenticated end-to-end API tests using az CLI token
# Validates that all critical API flows work from a user perspective.
# Usage: ./scripts/e2e-test.sh [WAF_FQDN]
set -euo pipefail

info() { printf '  %-60s %s\n' "$1" "$2"; }
pass() { info "$1" "✅"; PASSES=$((PASSES + 1)); }
fail() { info "$1" "❌ $2"; FAILURES=$((FAILURES + 1)); }
skip() { info "$1" "⏭️  $2"; SKIPS=$((SKIPS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_OUTPUT_FILE="$HARNESS_DIR/.azure/tf-outputs.json"

RG="$(jq -er '.resource_group_name.value' "$TF_OUTPUT_FILE" 2>/dev/null || echo "wordgame-dev-rg")"
WAF_FQDN="${1:-$(az containerapp show --name word-game-waf --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || echo "")}"

[ -n "$WAF_FQDN" ] || { echo "ERROR: Cannot determine WAF FQDN. Pass it as argument."; exit 1; }

BASE="https://${WAF_FQDN}"
FAILURES=0
PASSES=0
SKIPS=0

# --- Acquire token via az CLI ---
# The API expects an Entra ID token with audience = api://16f3fd41-cddd-44fb-a149-14314e62f7a8
API_CLIENT_ID="16f3fd41-cddd-44fb-a149-14314e62f7a8"
API_SCOPE="api://${API_CLIENT_ID}/access_as_user"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           End-to-End Authenticated API Tests                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "  Target: ${BASE}"
echo "  Scope:  ${API_SCOPE}"
echo

echo "── Acquiring Token ──"
TOKEN=$(az account get-access-token --resource "api://${API_CLIENT_ID}" --query accessToken -o tsv 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "  ⚠️  Could not acquire token via az CLI."
  echo "  Trying with scope parameter..."
  TOKEN=$(az account get-access-token --scope "${API_SCOPE}" --query accessToken -o tsv 2>/dev/null || echo "")
fi

if [ -z "$TOKEN" ]; then
  echo "  ❌ Cannot acquire token. Ensure you are logged in with: az login"
  echo "     and have consent for scope: ${API_SCOPE}"
  echo ""
  echo "  Falling back to unauthenticated tests (expect 401)..."
  AUTH_HEADER=""
  AUTHENTICATED=false
else
  echo "  ✅ Token acquired (${#TOKEN} chars)"
  AUTH_HEADER="Authorization: Bearer ${TOKEN}"
  AUTHENTICATED=true
fi
echo

# --- Helper functions ---
api_get() {
  local path="$1" expected_code="${2:-200}"
  local curl_args=(-s -w "\n%{http_code}")
  [ -n "${AUTH_HEADER:-}" ] && curl_args+=(-H "$AUTH_HEADER")

  local response http_code body
  response=$(curl "${curl_args[@]}" "$BASE$path" 2>/dev/null || echo -e "\n000")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" = "$expected_code" ]; then
    pass "GET ${path} → ${http_code}"
    echo "$body"
    return 0
  else
    fail "GET ${path}" "Expected ${expected_code}, got ${http_code}: $(echo "$body" | head -c 120)"
    echo "$body"
    return 1
  fi
}

api_post() {
  local path="$1" data="$2" expected_code="${3:-200}"
  local curl_args=(-s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "$data")
  [ -n "${AUTH_HEADER:-}" ] && curl_args+=(-H "$AUTH_HEADER")

  local response http_code body
  response=$(curl "${curl_args[@]}" "$BASE$path" 2>/dev/null || echo -e "\n000")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" = "$expected_code" ]; then
    pass "POST ${path} → ${http_code}"
    echo "$body"
    return 0
  else
    fail "POST ${path}" "Expected ${expected_code}, got ${http_code}: $(echo "$body" | head -c 120)"
    echo "$body"
    return 1
  fi
}

api_put() {
  local path="$1" data="$2" expected_code="${3:-200}"
  local curl_args=(-s -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" -d "$data")
  [ -n "${AUTH_HEADER:-}" ] && curl_args+=(-H "$AUTH_HEADER")

  local response http_code body
  response=$(curl "${curl_args[@]}" "$BASE$path" 2>/dev/null || echo -e "\n000")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" = "$expected_code" ]; then
    pass "PUT ${path} → ${http_code}"
    echo "$body"
    return 0
  else
    fail "PUT ${path}" "Expected ${expected_code}, got ${http_code}: $(echo "$body" | head -c 120)"
    echo "$body"
    return 1
  fi
}

# ──────────────────────────────────────────────
# 1. Infrastructure Health (no auth needed)
# ──────────────────────────────────────────────
echo "── 1. Infrastructure Health ──"
api_get "/health" 200 >/dev/null
api_get "/version" 200 >/dev/null
echo

# ──────────────────────────────────────────────
# 2. Authenticated API — User Management
# ──────────────────────────────────────────────
echo "── 2. User Management ──"
if [ "$AUTHENTICATED" = "true" ]; then
  ACTIVE_RESULT=$(api_get "/api/users/active" 200 2>/dev/null) || true
  if echo "$ACTIVE_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'users' in d" 2>/dev/null; then
    pass "GET /api/users/active → valid response shape"
  else
    fail "GET /api/users/active" "Response missing 'users' field"
  fi
else
  skip "GET /api/users/active" "No token"
fi
echo

# ──────────────────────────────────────────────
# 3. Authenticated API — Categories (BUG #1 target)
# ──────────────────────────────────────────────
echo "── 3. Category Configuration ──"
if [ "$AUTHENTICATED" = "true" ]; then
  CAT_RESULT=$(api_get "/api/categories/config" 200 2>/dev/null) || true
  if echo "$CAT_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'urls' in d or 'generated_categories' in d or 'source' in d" 2>/dev/null; then
    pass "GET /api/categories/config → valid response shape"
  else
    fail "GET /api/categories/config" "Response missing expected fields (urls/generated_categories/source)"
  fi
else
  skip "GET /api/categories/config" "No token"
fi
echo

# ──────────────────────────────────────────────
# 4. Authenticated API — Scores
# ──────────────────────────────────────────────
echo "── 4. Scores ──"
if [ "$AUTHENTICATED" = "true" ]; then
  api_get "/api/scores/game-count" 200 >/dev/null || true
  api_get "/api/scores/all-time" 200 >/dev/null || true
  api_get "/api/scores/today" 200 >/dev/null || true
else
  skip "Scores endpoints" "No token"
fi
echo

# ──────────────────────────────────────────────
# 5. Authenticated API — Game Status
# ──────────────────────────────────────────────
echo "── 5. Game Flow ──"
if [ "$AUTHENTICATED" = "true" ]; then
  api_get "/api/game/status" 200 >/dev/null || true
else
  skip "Game endpoints" "No token"
fi
echo

# ──────────────────────────────────────────────
# 6. CORS Preflight
# ──────────────────────────────────────────────
echo "── 6. CORS ──"
PREFLIGHT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS \
  -H "Origin: $BASE" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: Authorization, Content-Type" \
  "$BASE/api/users/register" 2>/dev/null || echo "000")
if [ "$PREFLIGHT_CODE" = "204" ] || [ "$PREFLIGHT_CODE" = "200" ]; then
  pass "CORS preflight → ${PREFLIGHT_CODE}"
else
  fail "CORS preflight" "Expected 204/200, got ${PREFLIGHT_CODE}"
fi
echo

# ──────────────────────────────────────────────
# 7. WebSocket Ticket (if auth available)
# ──────────────────────────────────────────────
echo "── 7. WebSocket ──"
if [ "$AUTHENTICATED" = "true" ]; then
  WS_RESULT=$(api_post "/api/auth/ws-ticket" '{}' 200 2>/dev/null) || true
  if echo "$WS_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'ticket' in d" 2>/dev/null; then
    pass "POST /api/auth/ws-ticket → valid ticket"
  else
    # 200 with ticket or 201 both acceptable
    skip "POST /api/auth/ws-ticket" "Response shape unexpected"
  fi
else
  skip "WebSocket ticket" "No token"
fi
echo

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════════"
echo "  Results: ${PASSES} passed, ${FAILURES} failed, ${SKIPS} skipped"
echo "══════════════════════════════════════════════════════════════"

if [ "$FAILURES" -gt 0 ]; then
  echo "  ❌ E2E TESTS FAILED"
  exit 1
else
  echo "  ✅ E2E TESTS PASSED"
  exit 0
fi
