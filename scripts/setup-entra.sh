#!/usr/bin/env bash
# setup-entra.sh — idempotently ensure the two Entra app registrations word-game needs:
#   1. API app     (exposes scope access_as_user; token audience for the FastAPI backend)
#   2. SPA app      (MSAL browser client; has delegated permission to the API scope)
#
# Writes resolved IDs to .azure/entra.json for azd-deploy.sh to consume.
# Requires: az CLI logged in with permission to create app registrations in the target tenant.
#
# Auth model (override via env):
#   ENTRA_SIGNIN_AUDIENCE  default AzureADandPersonalMicrosoftAccount  (personal MSA self-registration)
#   ENTRA_AUTHORITY        default https://login.microsoftonline.com/common
set -euo pipefail

info() { printf '[entra] %s\n' "$*"; }
die()  { printf '[entra][error] %s\n' "$*" >&2; exit 1; }

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
AZURE_DIR="$HARNESS_DIR/.azure"
ENTRA_JSON="$AZURE_DIR/entra.json"
mkdir -p "$AZURE_DIR"

command -v az >/dev/null || die "az CLI required"
command -v jq >/dev/null || die "jq required"

API_APP_NAME="${API_APP_NAME:-word-game-api}"
SPA_APP_NAME="${SPA_APP_NAME:-word-game-web}"
SIGNIN_AUDIENCE="${ENTRA_SIGNIN_AUDIENCE:-AzureADandPersonalMicrosoftAccount}"
# Redirect URIs are finalised by azd-deploy.sh once the WAF FQDN is known; seed localhost for dev.
SEED_REDIRECT="${SEED_REDIRECT:-http://localhost:5173/welcome}"

TENANT_ID="$(az account show --query tenantId -o tsv)"
info "tenant: $TENANT_ID"

# ── 1. API app registration ───────────────────────────────────────────────────
API_APP_ID="$(az ad app list --display-name "$API_APP_NAME" --query '[0].appId' -o tsv 2>/dev/null || true)"
if [[ -z "$API_APP_ID" || "$API_APP_ID" == "None" ]]; then
  info "creating API app '$API_APP_NAME'"
  API_APP_ID="$(az ad app create --display-name "$API_APP_NAME" \
    --sign-in-audience "$SIGNIN_AUDIENCE" --query appId -o tsv)"
else
  info "reusing API app '$API_APP_NAME' ($API_APP_ID)"
fi

# Application ID URI = api://<appId>; expose access_as_user delegated scope (via Graph PATCH,
# which reliably sets nested api.oauth2PermissionScopes where `az ad app update --set` cannot).
API_OBJ_ID="$(az ad app show --id "$API_APP_ID" --query id -o tsv)"
EXISTING_SCOPE="$(az ad app show --id "$API_APP_ID" --query "api.oauth2PermissionScopes[?value=='access_as_user'].id | [0]" -o tsv 2>/dev/null || true)"
if [[ -n "$EXISTING_SCOPE" && "$EXISTING_SCOPE" != "None" ]]; then
  SCOPE_ID="$EXISTING_SCOPE"
  info "access_as_user scope already present ($SCOPE_ID)"
else
  SCOPE_ID="$(uuidgen)"
  info "adding access_as_user scope via Microsoft Graph"
  BODY="$(cat <<JSON
{
  "identifierUris": ["api://$API_APP_ID"],
  "api": {
    "oauth2PermissionScopes": [{
      "adminConsentDescription": "Allow the app to access word-game API as the signed-in user.",
      "adminConsentDisplayName": "Access word-game API",
      "id": "$SCOPE_ID",
      "isEnabled": true,
      "type": "User",
      "userConsentDescription": "Allow this app to access the word-game API on your behalf.",
      "userConsentDisplayName": "Access word-game API",
      "value": "access_as_user"
    }]
  }
}
JSON
)"
  TMP_BODY="$(mktemp)"; printf '%s' "$BODY" > "$TMP_BODY"
  az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$API_OBJ_ID" \
    --headers "Content-Type=application/json" \
    --body "@$TMP_BODY" >/dev/null
  rm -f "$TMP_BODY"
fi
# Ensure the identifier URI is set (supported direct param; safe on both paths).
az ad app update --id "$API_APP_ID" --identifier-uris "api://$API_APP_ID" >/dev/null 2>&1 || true

# ── 2. SPA app registration ───────────────────────────────────────────────────
SPA_APP_ID="$(az ad app list --display-name "$SPA_APP_NAME" --query '[0].appId' -o tsv 2>/dev/null || true)"
if [[ -z "$SPA_APP_ID" || "$SPA_APP_ID" == "None" ]]; then
  info "creating SPA app '$SPA_APP_NAME'"
  SPA_APP_ID="$(az ad app create --display-name "$SPA_APP_NAME" \
    --sign-in-audience "$SIGNIN_AUDIENCE" --query appId -o tsv)"
else
  info "reusing SPA app '$SPA_APP_NAME' ($SPA_APP_ID)"
fi
# Set SPA-platform redirect URIs via Graph (az ad app create/update has no --spa-redirect-uris).
SPA_OBJ_ID="$(az ad app show --id "$SPA_APP_ID" --query id -o tsv)"
info "seeding SPA redirect URI ($SEED_REDIRECT)"
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$SPA_OBJ_ID" \
  --headers "Content-Type=application/json" \
  --body "{\"spa\":{\"redirectUris\":[\"$SEED_REDIRECT\"]}}" >/dev/null

# Grant the SPA delegated access to the API scope (idempotent).
info "granting SPA delegated permission to API access_as_user"
az ad app permission add --id "$SPA_APP_ID" \
  --api "$API_APP_ID" \
  --api-permissions "$SCOPE_ID=Scope" >/dev/null 2>&1 || info "permission already present"

# Ensure a service principal exists for each app (needed for token issuance / consent).
az ad sp show --id "$API_APP_ID" >/dev/null 2>&1 || az ad sp create --id "$API_APP_ID" >/dev/null
az ad sp show --id "$SPA_APP_ID" >/dev/null 2>&1 || az ad sp create --id "$SPA_APP_ID" >/dev/null

cat > "$ENTRA_JSON" <<JSON
{
  "tenant_id": "$TENANT_ID",
  "api_client_id": "$API_APP_ID",
  "spa_client_id": "$SPA_APP_ID",
  "api_scope": "api://$API_APP_ID/access_as_user",
  "sign_in_audience": "$SIGNIN_AUDIENCE"
}
JSON
info "wrote $ENTRA_JSON"
info "API app:  $API_APP_ID"
info "SPA app:  $SPA_APP_ID"
info "Done. Run scripts/azd-deploy.sh to build+deploy (it finalises SPA redirect URIs with the WAF FQDN)."
