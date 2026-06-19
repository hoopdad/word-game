#!/usr/bin/env bash
# scripts/get-e2e-token.sh — Acquire an API token for e2e testing via device code flow
# First run: interactive (user visits URL and enters code)
# Subsequent runs: uses cached refresh token (no interaction needed)
#
# Usage: TOKEN=$(./scripts/get-e2e-token.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
TENANT_ID="d52a6857-5f44-4f8f-bcc8-420952d3225d"
WEB_CLIENT_ID="b4d29652-ff30-43ea-90f6-830cc340f866"
API_CLIENT_ID="16f3fd41-cddd-44fb-a149-14314e62f7a8"
SCOPE="api://${API_CLIENT_ID}/access_as_user offline_access"
TOKEN_CACHE="$HARNESS_DIR/.azure/e2e-token-cache.json"

mkdir -p "$(dirname "$TOKEN_CACHE")"

# --- Try cached token first ---
if [ -f "$TOKEN_CACHE" ]; then
  EXPIRES_AT=$(python3 -c "import json; print(json.load(open('$TOKEN_CACHE')).get('expires_at',0))" 2>/dev/null || echo "0")
  NOW=$(date +%s)

  if [ "$NOW" -lt "$EXPIRES_AT" ]; then
    # Token still valid
    python3 -c "import json; print(json.load(open('$TOKEN_CACHE'))['access_token'])" 2>/dev/null
    exit 0
  fi

  # Try refresh
  REFRESH_TOKEN=$(python3 -c "import json; print(json.load(open('$TOKEN_CACHE')).get('refresh_token',''))" 2>/dev/null || echo "")
  if [ -n "$REFRESH_TOKEN" ]; then
    REFRESH_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=refresh_token&client_id=${WEB_CLIENT_ID}&refresh_token=${REFRESH_TOKEN}&scope=${SCOPE// /%20}" 2>/dev/null)

    ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")
    if [ -n "$ACCESS_TOKEN" ] && echo "$ACCESS_TOKEN" | grep -q '^eyJ'; then
      # Save refreshed tokens
      python3 -c "
import json,sys,time
d = json.loads('''$REFRESH_RESPONSE''')
d['expires_at'] = int(time.time()) + d.get('expires_in', 3600) - 60
json.dump(d, open('$TOKEN_CACHE', 'w'))
" 2>/dev/null
      echo "$ACCESS_TOKEN"
      exit 0
    fi
  fi
fi

# --- Device code flow (interactive first time) ---
echo "=== E2E Token Acquisition (Device Code Flow) ===" >&2

DEVICE_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/devicecode" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${WEB_CLIENT_ID}&scope=${SCOPE// /%20}" 2>/dev/null)

DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['device_code'])" 2>/dev/null)
USER_CODE=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_code'])" 2>/dev/null)
VERIFY_URI=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['verification_uri'])" 2>/dev/null)
INTERVAL=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('interval',5))" 2>/dev/null)
EXPIRES_IN=$(echo "$DEVICE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('expires_in',900))" 2>/dev/null)

if [ -z "$DEVICE_CODE" ] || [ -z "$USER_CODE" ]; then
  echo "ERROR: Failed to start device code flow" >&2
  echo "$DEVICE_RESPONSE" >&2
  exit 1
fi

echo "" >&2
echo "  🔐 Go to: ${VERIFY_URI}" >&2
echo "  📋 Enter code: ${USER_CODE}" >&2
echo "" >&2
echo "  Waiting for authentication (expires in ${EXPIRES_IN}s)..." >&2

# Poll for token
ELAPSED=0
while [ "$ELAPSED" -lt "$EXPIRES_IN" ]; do
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))

  TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=${WEB_CLIENT_ID}&device_code=${DEVICE_CODE}" 2>/dev/null)

  ERROR=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error',''))" 2>/dev/null || echo "")

  case "$ERROR" in
    authorization_pending)
      printf "." >&2
      ;;
    slow_down)
      INTERVAL=$((INTERVAL + 5))
      ;;
    "")
      # Success!
      ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
      if [ -n "$ACCESS_TOKEN" ] && echo "$ACCESS_TOKEN" | grep -q '^eyJ'; then
        echo "" >&2
        echo "  ✅ Authenticated! Token cached for future runs." >&2

        # Cache the token
        python3 -c "
import json,time
d = json.loads('''$(echo "$TOKEN_RESPONSE" | sed "s/'/'\\\\''/g")''')
d['expires_at'] = int(time.time()) + d.get('expires_in', 3600) - 60
json.dump(d, open('$TOKEN_CACHE', 'w'))
" 2>/dev/null

        echo "$ACCESS_TOKEN"
        exit 0
      fi
      ;;
    *)
      echo "" >&2
      echo "  ❌ Error: $ERROR" >&2
      echo "$TOKEN_RESPONSE" >&2
      exit 1
      ;;
  esac
done

echo "" >&2
echo "  ❌ Timed out waiting for authentication" >&2
exit 1
