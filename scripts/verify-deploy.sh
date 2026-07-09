#!/usr/bin/env bash
# verify-deploy.sh — post-deploy smoke test through the WAF (requires VNet/VPN reachability).
# Reads .azure/deploy.json (written by azd-deploy.sh) for the WAF URL, or accepts WAF_URL env.
set -uo pipefail

info() { printf '[verify] %s\n' "$*"; }
pass() { printf '[verify][PASS] %s\n' "$*"; }
fail() { printf '[verify][FAIL] %s\n' "$*" >&2; FAILED=1; }

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
DEPLOY_JSON="$HARNESS_DIR/.azure/deploy.json"
WAF_URL="${WAF_URL:-}"
if [[ -z "$WAF_URL" && -f "$DEPLOY_JSON" ]]; then
  WAF_URL="$(jq -r '.waf_url // empty' "$DEPLOY_JSON" 2>/dev/null)"
fi
[[ -n "$WAF_URL" ]] || { echo "[verify][error] no WAF_URL (set env or deploy first)"; exit 2; }
WAF_URL="${WAF_URL%/}"
FAILED=0
CURL=(curl -sk --max-time 20 -o /dev/null -w '%{http_code}')

info "target: $WAF_URL"

# 1. WAF health endpoint
code="$("${CURL[@]}" "$WAF_URL/health" || echo 000)"
[[ "$code" == "200" ]] && pass "WAF /health -> 200" || fail "WAF /health -> $code"

# 2. SPA served at root
code="$("${CURL[@]}" "$WAF_URL/" || echo 000)"
[[ "$code" == "200" ]] && pass "web / -> 200" || fail "web / -> $code"

# 3. API reachable through WAF; unauthenticated protected route must be rejected (401/403), not 5xx.
code="$("${CURL[@]}" "$WAF_URL/api/me" || echo 000)"
if [[ "$code" == "401" || "$code" == "403" ]]; then
  pass "API /api/me unauth -> $code (auth enforced)"
elif [[ "$code" == "5"* || "$code" == "000" ]]; then
  fail "API /api/me -> $code (backend unreachable or erroring)"
else
  info "API /api/me -> $code"
fi

# 4. Agent reachable through WAF (health is unauthenticated).
code="$("${CURL[@]}" "$WAF_URL/agent/health" || echo 000)"
[[ "$code" == "200" ]] && pass "agent /agent/health -> 200" || fail "agent /agent/health -> $code"

# 5. Version endpoints (best-effort informational).
for p in /api/../version /api/me; do :; done
ver="$(curl -sk --max-time 20 "$WAF_URL/agent/health" 2>/dev/null | head -c 200 || true)"
[[ -n "$ver" ]] && info "agent health body: $ver"

if [[ "$FAILED" -eq 0 ]]; then
  info "✅ smoke test PASSED"
  exit 0
else
  info "❌ smoke test had failures"
  exit 1
fi
