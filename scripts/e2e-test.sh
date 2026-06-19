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
TOKEN=""

# Method 1: Environment variable (for CI/automated testing)
if [ -n "${E2E_TOKEN:-}" ]; then
  TOKEN="$E2E_TOKEN"
  echo "  ✅ Token from E2E_TOKEN env var (${#TOKEN} chars)"
fi

# Method 2: Service principal credentials (for CI)
if [ -z "$TOKEN" ] && [ -n "${E2E_SP_CLIENT_ID:-}" ] && [ -n "${E2E_SP_CLIENT_SECRET:-}" ]; then
  TENANT_ID="${E2E_SP_TENANT_ID:-d52a6857-5f44-4f8f-bcc8-420952d3225d}"
  TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${E2E_SP_CLIENT_ID}&client_secret=${E2E_SP_CLIENT_SECRET}&scope=api://${API_CLIENT_ID}/.default" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ] && echo "$TOKEN" | grep -q '^eyJ'; then
    echo "  ✅ Token from service principal (${#TOKEN} chars)"
  else
    TOKEN=""
  fi
fi

# Method 3: Device code flow token cache (non-interactive — uses cached token only)
# Run `./scripts/get-e2e-token.sh` manually first to populate the cache
if [ -z "$TOKEN" ] && [ -f "$SCRIPT_DIR/../.azure/e2e-token-cache.json" ]; then
  TOKEN=$(timeout 5 "$SCRIPT_DIR/get-e2e-token.sh" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ] && echo "$TOKEN" | grep -q '^eyJ'; then
    echo "  ✅ Token from device code cache (${#TOKEN} chars)"
  else
    TOKEN=""
  fi
fi

# Method 4: az CLI (if user has granted consent)
if [ -z "$TOKEN" ]; then
  TOKEN=$(timeout 10 az account get-access-token --resource "api://${API_CLIENT_ID}" --query accessToken -o tsv 2>/dev/null || echo "")
  if [ -n "$TOKEN" ] && [ "${#TOKEN}" -gt 100 ] && echo "$TOKEN" | grep -q '^eyJ'; then
    echo "  ✅ Token from az CLI (${#TOKEN} chars)"
  else
    TOKEN=""
  fi
fi

if [ -z "$TOKEN" ]; then
  echo "  ⚠️  No token available. Running unauthenticated validation mode."
  echo "     To enable full user simulation, run: ./scripts/get-e2e-token.sh"
  echo "     (one-time device code auth, then tokens are cached automatically)"
  AUTH_HEADER=""
  AUTHENTICATED=false
else
  AUTH_HEADER="Authorization: Bearer ${TOKEN}"
  AUTHENTICATED=true
fi
echo

# --- Helper functions ---
# pass/fail go to stderr (display), body goes to stdout (capture)
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

# Fetch body only (no pass/fail side effects)
fetch() {
  local method="$1" path="$2" data="${3:-}"
  local curl_args=(-s -w "\n%{http_code}")
  [ -n "${AUTH_HEADER:-}" ] && curl_args+=(-H "$AUTH_HEADER")
  if [ "$method" != "GET" ]; then
    curl_args+=(-X "$method" -H "Content-Type: application/json")
    [ -n "$data" ] && curl_args+=(-d "$data")
  fi

  local response
  response=$(curl "${curl_args[@]}" "$BASE$path" 2>/dev/null || echo -e "\n000")
  local http_code body
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  # Return: body on stdout, code on fd3
  echo "$body"
  return 0
}

fetch_code() {
  local method="$1" path="$2" data="${3:-}"
  local curl_args=(-s -o /dev/null -w "%{http_code}")
  [ -n "${AUTH_HEADER:-}" ] && curl_args+=(-H "$AUTH_HEADER")
  if [ "$method" != "GET" ]; then
    curl_args+=(-X "$method" -H "Content-Type: application/json")
    [ -n "$data" ] && curl_args+=(-d "$data")
  fi
  curl "${curl_args[@]}" "$BASE$path" 2>/dev/null || echo "000"
}

# ══════════════════════════════════════════════════════════════
# USER BEHAVIOR SIMULATION
# Chains curl calls to replicate what a real user does in the UI
# ══════════════════════════════════════════════════════════════

if [ "$AUTHENTICATED" = "true" ]; then
  # ────────────────────────────────────────────
  # Flow 1: New user arrives → registers → sees dashboard
  # ────────────────────────────────────────────
  echo "── Flow 1: User Registration & Dashboard ──"

  # User registers their display name (201=new, 409=already exists)
  REG_CODE=$(fetch_code POST "/api/users/register" '{"display_name":"E2E TestUser"}')
  if [ "$REG_CODE" = "201" ] || [ "$REG_CODE" = "409" ]; then
    pass "Register user → ${REG_CODE} (${REG_CODE/201/new}${REG_CODE/409/exists})"
  else
    fail "POST /api/users/register" "Expected 201|409, got ${REG_CODE}"
  fi

  # User lands on dashboard, sees active users
  ACTIVE_BODY=$(fetch GET "/api/users/active")
  if echo "$ACTIVE_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d.get('users'), list)" 2>/dev/null; then
    pass "Dashboard shows active users list"
  else
    fail "Dashboard /api/users/active" "Missing 'users' array: $(echo "$ACTIVE_BODY" | head -c 80)"
  fi

  # User checks if a name is available
  NAME_CODE=$(fetch_code GET "/api/users/check-name/SomeRandomName")
  if [ "$NAME_CODE" = "200" ]; then
    pass "Check name availability → 200"
  else
    fail "GET /api/users/check-name" "Expected 200, got $NAME_CODE"
  fi
  echo

  # ────────────────────────────────────────────
  # Flow 2: User configures categories for the game
  # ────────────────────────────────────────────
  echo "── Flow 2: Configure Categories ──"

  # User loads current config
  CAT_BODY=$(fetch GET "/api/categories/config")
  if echo "$CAT_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'source' in d" 2>/dev/null; then
    pass "Load current category config"
  else
    fail "GET /api/categories/config" "Missing 'source': $(echo "$CAT_BODY" | head -c 80)"
  fi

  # User submits new category config (parse current, modify, submit)
  SUBMIT_CODE=$(fetch_code PUT "/api/categories/config" '{"urls":["https://example.com/words"],"generated_categories":["Animals","Geography"]}')
  if [ "$SUBMIT_CODE" = "200" ]; then
    pass "Submit category config change → 200"
  else
    fail "PUT /api/categories/config" "Expected 200, got $SUBMIT_CODE"
  fi

  # User reloads page — verifies config persisted
  CAT_RELOAD=$(fetch GET "/api/categories/config")
  if echo "$CAT_RELOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'https://example.com/words' in d.get('urls',[])" 2>/dev/null; then
    pass "Category config persisted after reload"
  else
    fail "Config persistence" "URL not in reloaded config: $(echo "$CAT_RELOAD" | head -c 80)"
  fi
  echo

  # ────────────────────────────────────────────
  # Flow 3: User checks scores and enters game lobby
  # ────────────────────────────────────────────
  echo "── Flow 3: Scores & Game Lobby ──"

  # User views leaderboard
  SCORES_BODY=$(fetch GET "/api/scores/all-time")
  if echo "$SCORES_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'scores' in d" 2>/dev/null; then
    pass "View all-time leaderboard"
  else
    fail "GET /api/scores/all-time" "Missing 'scores': $(echo "$SCORES_BODY" | head -c 80)"
  fi

  SCORES_CODE=$(fetch_code GET "/api/scores/today")
  [ "$SCORES_CODE" = "200" ] && pass "View today's scores → 200" || fail "GET /api/scores/today" "Got $SCORES_CODE"

  COUNT_CODE=$(fetch_code GET "/api/scores/game-count")
  [ "$COUNT_CODE" = "200" ] && pass "Get game count → 200" || fail "GET /api/scores/game-count" "Got $COUNT_CODE"

  # User checks game lobby status
  GAME_BODY=$(fetch GET "/api/game/status")
  if echo "$GAME_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'status' in d" 2>/dev/null; then
    pass "Game lobby status → $(echo "$GAME_BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null)"
  else
    fail "GET /api/game/status" "Missing 'status': $(echo "$GAME_BODY" | head -c 80)"
  fi
  echo

  # ────────────────────────────────────────────
  # Flow 4: User requests WebSocket ticket for real-time play
  # ────────────────────────────────────────────
  echo "── Flow 4: WebSocket Connection ──"

  WS_BODY=$(fetch POST "/api/auth/ws-ticket" '{}')
  if echo "$WS_BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'ticket' in d and len(d['ticket']) > 10" 2>/dev/null; then
    pass "Obtain WebSocket ticket for real-time play"
  else
    fail "POST /api/auth/ws-ticket" "Invalid ticket: $(echo "$WS_BODY" | head -c 80)"
  fi
  echo

  # ────────────────────────────────────────────
  # Flow 5: User updates profile
  # ────────────────────────────────────────────
  echo "── Flow 5: Profile Update ──"

  PROFILE_CODE=$(fetch_code PUT "/api/users/profile" '{"display_name":"E2E Updated"}')
  if [ "$PROFILE_CODE" = "200" ]; then
    pass "Update display name → 200"
  else
    fail "PUT /api/users/profile → $PROFILE_CODE" "(known bug: Cosmos enable_cross_partition_query)"
  fi
  echo

  # ────────────────────────────────────────────
  # Flow 6: CORS (browser enforces this on every API call)
  # ────────────────────────────────────────────
  echo "── Flow 6: CORS Preflight ──"

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

else
  # ════════════════════════════════════════════
  # UNAUTHENTICATED MODE: verify API is alive (401, not 500)
  # ════════════════════════════════════════════
  echo "── Unauthenticated Smoke Test (401 = healthy) ──"
  echo "  (Run ./scripts/get-e2e-token.sh once to enable full user simulation)"
  echo

  for ep in "/api/users/active" "/api/categories/config" "/api/scores/all-time" \
            "/api/scores/today" "/api/scores/game-count" "/api/game/status"; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE$ep" 2>/dev/null)
    if [ "$CODE" = "401" ]; then
      pass "GET $ep → 401 (healthy)"
    elif [ "$CODE" = "500" ]; then
      fail "GET $ep" "500 = backend crash"
    else
      fail "GET $ep" "Expected 401, got $CODE"
    fi
  done

  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{}' "$BASE/api/auth/ws-ticket" 2>/dev/null)
  if [ "$CODE" = "401" ]; then
    pass "POST /api/auth/ws-ticket → 401 (healthy)"
  else
    fail "POST /api/auth/ws-ticket" "Expected 401, got $CODE"
  fi

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
