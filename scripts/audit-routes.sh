#!/usr/bin/env bash
# scripts/audit-routes.sh — Cross-validate frontend API calls, WAF routing, and backend routes
# Run from word-game-harness root before deploying to catch mismatches early.
set -euo pipefail

info() { printf '  %-50s %s\n' "$1" "$2"; }
pass() { info "$1" "✅"; }
fail() { info "$1" "❌ $2"; FAILURES=$((FAILURES + 1)); }
warn() { info "$1" "⚠️  $2"; WARNINGS=$((WARNINGS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$(cd "$HARNESS_DIR/../word-game-web" && pwd)"
API_DIR="$(cd "$HARNESS_DIR/../word-game-api" && pwd)"
WAF_DIR="$(cd "$HARNESS_DIR/../word-game-waf" && pwd)"

FAILURES=0
WARNINGS=0

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           API Route & Contract Audit                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo

# ──────────────────────────────────────────────
# 1. Extract frontend API calls from apiClient.ts
# ──────────────────────────────────────────────
echo "── Frontend API Calls (apiClient.ts) ──"
API_CLIENT="$WEB_DIR/src/services/apiClient.ts"
[ -f "$API_CLIENT" ] || { echo "ERROR: apiClient.ts not found"; exit 1; }

# Extract method + path pairs (paths start with / in source)
FRONTEND_CALLS=$(grep -oP "this\.client\.(get|post|put|patch|delete)\s*\(\s*['\"\`](\/?[^'\"\`\$]+)" "$API_CLIENT" | \
  sed -E "s/this\.client\.(get|post|put|patch|delete)\(['\"\`]//" | \
  sed "s/['\"\`].*//")

FRONTEND_METHODS=$(grep -oP '\bthis\.client\.\K(get|post|put|patch|delete)' "$API_CLIENT")

paste <(echo "$FRONTEND_METHODS" | tr '[:lower:]' '[:upper:]') <(echo "$FRONTEND_CALLS") | while IFS=$'\t' read -r method path; do
  info "${method} ${path}" "(frontend)"
done
echo

# ──────────────────────────────────────────────
# 2. Extract backend routes from FastAPI main.py
# ──────────────────────────────────────────────
echo "── Backend Routes (main.py) ──"
API_MAIN="$API_DIR/app/main.py"
[ -f "$API_MAIN" ] || { echo "ERROR: main.py not found"; exit 1; }

BACKEND_ROUTES=$(grep -oP '@app\.(get|post|put|patch|delete|websocket)\s*\(\s*"([^"]+)"' "$API_MAIN" | \
  sed 's/@app\.\(get\|post\|put\|patch\|delete\|websocket\)("//' | sed 's/"//')
BACKEND_METHODS=$(grep -oP '@app\.\K(get|post|put|patch|delete|websocket)' "$API_MAIN")

paste <(echo "$BACKEND_METHODS" | tr '[:lower:]' '[:upper:]') <(echo "$BACKEND_ROUTES") | sort -u | while IFS=$'\t' read -r method path; do
  info "${method} ${path}" "(backend)"
done
echo

# ──────────────────────────────────────────────
# 3. Check WAF nginx routing
# ──────────────────────────────────────────────
echo "── WAF Nginx Locations ──"
WAF_CONF="$WAF_DIR/docker/nginx/nginx.conf.template"
[ -f "$WAF_CONF" ] || { echo "ERROR: nginx.conf.template not found"; exit 1; }

grep -oP 'location\s+\S+\s+\S+|location\s+\S+' "$WAF_CONF" | while read -r loc; do
  upstream=$(grep -A5 "$loc" "$WAF_CONF" | grep -oP 'proxy_pass\s+\K\S+' | head -1 || echo "static/return")
  info "$loc" "→ ${upstream:-local}"
done
echo

# ──────────────────────────────────────────────
# 4. Cross-validate: frontend path + /api base → backend route
# ──────────────────────────────────────────────
echo "── Cross-Validation: Frontend → WAF → Backend ──"

paste <(echo "$FRONTEND_METHODS" | tr '[:lower:]' '[:upper:]') <(echo "$FRONTEND_CALLS") | while IFS=$'\t' read -r method path; do
  # Frontend paths start with / already, prepend /api
  full_path="/api${path}"

  # Check WAF will route /api/* to API upstream
  if ! grep -q 'location.*\^~.*/api/' "$WAF_CONF"; then
    fail "${method} ${path}" "WAF has no /api/ proxy location"
    continue
  fi

  # Normalize path: strip template expressions, trailing slashes → {param}
  clean_path=$(echo "$full_path" | sed 's/\${[^}]*}/{param}/g' | sed 's/\/$//')
  # If path was truncated at template literal, treat trailing / as parameterized
  if [ "$clean_path" != "$full_path" ] || echo "$full_path" | grep -q '/$'; then
    clean_path="${clean_path%/}"
    # Try matching with optional trailing param
    try_with_param=true
  else
    try_with_param=false
  fi

  # Check backend has this route (exact or parameterized)
  method_lower=$(echo "$method" | tr '[:upper:]' '[:lower:]')
  found=false

  while IFS= read -r backend_route; do
    # Normalize backend route params for comparison
    clean_backend=$(echo "$backend_route" | sed 's/{[^}]*}/{param}/g')
    if [ "$clean_path" = "$clean_backend" ]; then
      found=true
      break
    fi
    # Also match if frontend path is a prefix (truncated template param)
    if [ "$try_with_param" = "true" ] && echo "$clean_backend" | grep -q "^${clean_path}/"; then
      found=true
      break
    fi
  done < <(grep -oP "@app\.${method_lower}\(\"([^\"]+)\"" "$API_MAIN" | sed "s/@app\.${method_lower}(\"//;s/\"//")

  if [ "$found" = "true" ]; then
    pass "${method} ${full_path}"
  else
    fail "${method} ${full_path}" "No matching backend route"
  fi
done
echo

# ──────────────────────────────────────────────
# 5. Check payload field names against contract
# ──────────────────────────────────────────────
echo "── Payload Field Name Validation ──"

# Extract POST/PUT request body KEYS only (left side of : in object literals)
# Pattern: .post('/path', { key1: val, key2: val })
CAMEL_FIELDS=$(grep -oP 'this\.client\.(post|put)\([^)]+\{[^}]+\}' "$API_CLIENT" | \
  grep -oP '\{\s*\K[^}]+' | \
  tr ',' '\n' | \
  grep -oP '^\s*\K[a-zA-Z_]+(?=\s*:)' | \
  grep -P '^[a-z]+[A-Z]' || true)

if [ -n "$CAMEL_FIELDS" ]; then
  echo "$CAMEL_FIELDS" | while read -r field; do
    fail "camelCase field: ${field}" "API expects snake_case — check .contracts/*.yml"
  done
else
  pass "All payload fields use snake_case"
fi
echo

# ──────────────────────────────────────────────
# 6. Check VITE_API_BASE_URL in deploy script
# ──────────────────────────────────────────────
echo "── Build-time Env Var Validation ──"

DEPLOY_SCRIPT="$HARNESS_DIR/scripts/azd-deploy.sh"
if [ -f "$DEPLOY_SCRIPT" ]; then
  BASE_URL=$(grep -oP 'VITE_API_BASE_URL=\K[^"]+' "$DEPLOY_SCRIPT" | head -1)
  if [ "$BASE_URL" = "/api" ]; then
    pass "VITE_API_BASE_URL=/api"
  elif [ -z "$BASE_URL" ]; then
    fail "VITE_API_BASE_URL" "Empty — will fall back to localhost:5000"
  else
    warn "VITE_API_BASE_URL=${BASE_URL}" "Expected /api for WAF proxy"
  fi

  WS_URL=$(grep -oP 'VITE_WS_BASE_URL=\K[^"]*' "$DEPLOY_SCRIPT" | head -1)
  if [ -z "$WS_URL" ]; then
    pass "VITE_WS_BASE_URL=(empty → runtime derivation)"
  else
    warn "VITE_WS_BASE_URL=${WS_URL}" "Non-empty — may not match deployed origin"
  fi
else
  warn "azd-deploy.sh" "Deploy script not found"
fi

# Check apiClient.ts fallback
FALLBACK=$(grep -oP "import\.meta\.env\.VITE_API_BASE_URL\s*\|\|\s*['\"]([^'\"]+)" "$API_CLIENT" | grep -oP "'[^']+'" | tr -d "'" || true)
if [ -n "$FALLBACK" ]; then
  if echo "$FALLBACK" | grep -q "localhost"; then
    pass "Localhost fallback (dev only): ${FALLBACK}"
  fi
fi
echo

# ──────────────────────────────────────────────
# 7. Check WebSocket routing
# ──────────────────────────────────────────────
echo "── WebSocket Routing ──"

if grep -q 'location.*=.*/ws' "$WAF_CONF"; then
  if grep -qP "@app\.websocket\(\"/ws\"\)" "$API_MAIN"; then
    pass "WebSocket /ws route"
  else
    fail "WebSocket /ws" "WAF routes /ws but no backend @app.websocket"
  fi
else
  warn "WebSocket" "No /ws location in WAF config"
fi
echo

# ──────────────────────────────────────────────
# 8. Response shape validation (apiClient extraction)
# ──────────────────────────────────────────────
echo "── Response Shape Validation ──"

# Check that apiClient methods extracting data from response use .data.FIELD, not bare .data
# Pattern: methods that return response.data directly (no field access) are risky — API
# returns wrapped objects like {scores: [...]} not raw arrays
RAW_DATA_RETURNS=$(grep -nP 'return\s+response\.data\s*$' "$API_CLIENT" || true)
if [ -n "$RAW_DATA_RETURNS" ]; then
  echo "$RAW_DATA_RETURNS" | while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    fail "apiClient.ts:${lineno}" "Returns raw response.data — API likely wraps in {field: [...]}"
  done
else
  pass "All apiClient methods extract specific fields from response"
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
  echo "RESULT: PASS — all routes validated"
  exit 0
fi
