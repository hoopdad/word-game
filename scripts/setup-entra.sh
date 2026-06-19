#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*" >&2; }
ok() { printf '[OK] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
    return
  fi

  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return
  fi

  die "Unable to generate a UUID; install uuidgen or python3"
}

json_escape() {
  local value="${1//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

json_array_from_stream() {
  local first=1
  local line

  printf '['
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    printf '"%s"' "$(json_escape "$line")"
    first=0
  done
  printf ']'
}

trim_and_unique() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk 'NF && !seen[$0]++'
}

csv_to_lines() {
  printf '%s\n' "$1" | tr ',' '\n' | trim_and_unique
}

require_single_app_match() {
  local display_name="$1"
  local count

  count="$(az ad app list --display-name "$display_name" --query 'length(@)' -o tsv --only-show-errors)"
  case "$count" in
    0|1) ;;
    *)
      die "Found ${count} app registrations named ${display_name}; resolve duplicates before rerunning"
      ;;
  esac
}

wait_for_application() {
  local app_id="$1"
  local attempt=1

  until az ad app show --id "$app_id" --query appId -o tsv --only-show-errors >/dev/null 2>&1; do
    if [ "$attempt" -ge 20 ]; then
      die "Timed out waiting for application ${app_id} to become readable"
    fi
    sleep 2
    attempt=$((attempt + 1))
  done
}

wait_for_service_principal() {
  local app_id="$1"
  local attempt=1

  until az ad sp show --id "$app_id" --query appId -o tsv --only-show-errors >/dev/null 2>&1; do
    if [ "$attempt" -ge 20 ]; then
      die "Timed out waiting for service principal ${app_id} to become readable"
    fi
    sleep 3
    attempt=$((attempt + 1))
  done
}

ensure_app() {
  local display_name="$1"
  local audience="$2"
  local app_id

  require_single_app_match "$display_name"
  app_id="$(az ad app list --display-name "$display_name" --query '[0].appId' -o tsv --only-show-errors)"

  if [ -z "${app_id:-}" ] || [ "$app_id" = "None" ]; then
    info "Creating app registration: ${display_name}"
    app_id="$(az ad app create \
      --display-name "$display_name" \
      --sign-in-audience "$audience" \
      --query appId \
      -o tsv \
      --only-show-errors)"
    ok "Created app registration: ${display_name}"
  else
    info "Reusing app registration: ${display_name}"
  fi

  wait_for_application "$app_id"
  az ad app update --id "$app_id" --sign-in-audience "$audience" --only-show-errors >/dev/null
  printf '%s\n' "$app_id"
}

ensure_service_principal() {
  local app_id="$1"

  if ! az ad sp show --id "$app_id" --query id -o tsv --only-show-errors >/dev/null 2>&1; then
    info "Creating service principal for app ${app_id}"
    az ad sp create --id "$app_id" --only-show-errors >/dev/null
    ok "Created service principal for app ${app_id}"
  else
    info "Reusing service principal for app ${app_id}"
  fi

  wait_for_service_principal "$app_id"
  az ad sp show --id "$app_id" --query id -o tsv --only-show-errors
}

graph_patch_application() {
  local object_id="$1"
  local body="$2"
  local label="$3"

  az rest \
    --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/${object_id}" \
    --headers 'Content-Type=application/json' \
    --body "$body" \
    --only-show-errors >/dev/null
  ok "Updated ${label}"
}

existing_spa_redirects() {
  local app_id="$1"
  az ad app show --id "$app_id" --query 'spa.redirectUris[]' -o tsv --only-show-errors 2>/dev/null || true
}

existing_public_client_redirects() {
  local app_id="$1"
  az ad app show --id "$app_id" --query 'publicClient.redirectUris[]' -o tsv --only-show-errors 2>/dev/null || true
}

detected_waf_redirect() {
  local fqdn
  fqdn="$(
    az containerapp show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$WAF_APP_NAME" \
      --query 'properties.configuration.ingress.fqdn' \
      -o tsv \
      --only-show-errors 2>/dev/null || true
  )"

  if [ -n "${fqdn:-}" ] && [ "$fqdn" != "None" ]; then
    printf 'https://%s/auth/callback\n' "$fqdn"
  fi
}

build_spa_redirects_json() {
  {
    existing_spa_redirects "$WEB_APP_ID"
    if [ -n "${WEB_REDIRECT_URIS:-}" ]; then
      csv_to_lines "$WEB_REDIRECT_URIS"
    else
      printf '%s\n' 'http://localhost:5173/auth/callback'
      detected_waf_redirect
    fi
  } | trim_and_unique | json_array_from_stream
}

build_public_client_redirects_json() {
  {
    existing_public_client_redirects "$WEB_APP_ID"
    if [ -n "${PUBLIC_CLIENT_REDIRECT_URIS:-}" ]; then
      csv_to_lines "$PUBLIC_CLIENT_REDIRECT_URIS"
    else
      printf '%s\n' 'https://login.microsoftonline.com/common/oauth2/nativeclient'
    fi
  } | trim_and_unique | json_array_from_stream
}

ensure_federated_credential() {
  local app_id="$1"
  local name="$2"
  local subject="$3"
  local description="$4"
  local exists
  local create_body
  local update_body

  exists="$(
    az ad app federated-credential list \
      --id "$app_id" \
      --query "[?name=='${name}'] | length(@)" \
      -o tsv \
      --only-show-errors
  )"

  create_body="$(cat <<EOF
{"name":"$(json_escape "$name")","issuer":"https://token.actions.githubusercontent.com","subject":"$(json_escape "$subject")","description":"$(json_escape "$description")","audiences":["api://AzureADTokenExchange"]}
EOF
)"

  update_body="$(cat <<EOF
{"issuer":"https://token.actions.githubusercontent.com","subject":"$(json_escape "$subject")","description":"$(json_escape "$description")","audiences":["api://AzureADTokenExchange"]}
EOF
)"

  if [ "$exists" = "0" ]; then
    az ad app federated-credential create \
      --id "$app_id" \
      --parameters "$create_body" \
      --only-show-errors >/dev/null
    ok "Created federated credential: ${name}"
  else
    az ad app federated-credential update \
      --id "$app_id" \
      --federated-credential-id "$name" \
      --parameters "$update_body" \
      --only-show-errors >/dev/null
    ok "Updated federated credential: ${name}"
  fi
}

ensure_contributor_role_assignment() {
  local principal_object_id="$1"
  local assignment_count

  assignment_count="$(
    az role assignment list \
      --assignee-object-id "$principal_object_id" \
      --scope "$RESOURCE_GROUP_ID" \
      --role Contributor \
      --fill-principal-name false \
      --fill-role-definition-name false \
      --query 'length(@)' \
      -o tsv \
      --only-show-errors
  )"

  if [ "$assignment_count" = "0" ]; then
    az role assignment create \
      --assignee-object-id "$principal_object_id" \
      --assignee-principal-type ServicePrincipal \
      --role Contributor \
      --scope "$RESOURCE_GROUP_ID" \
      --only-show-errors >/dev/null
    ok "Granted Contributor on ${RESOURCE_GROUP}"
  else
    ok "Contributor role assignment already exists on ${RESOURCE_GROUP}"
  fi
}

ensure_external_id_user_flow() {
  local create_body

  if az rest \
    --method GET \
    --url "https://graph.microsoft.com/beta/identity/b2cUserFlows/${FLOW_NAME}" \
    --only-show-errors >/dev/null 2>&1; then
    ok "External ID user flow already exists: ${FLOW_NAME}"
    return
  fi

  create_body="$(cat <<EOF
{"id":"$(json_escape "$FLOW_NAME")","userFlowType":"signUpOrSignIn","userFlowTypeVersion":1,"defaultLanguageTag":"en","isLanguageCustomizationEnabled":false}
EOF
)"

  az rest \
    --method POST \
    --url 'https://graph.microsoft.com/beta/identity/b2cUserFlows' \
    --headers 'Content-Type=application/json' \
    --body "$create_body" \
    --only-show-errors >/dev/null
  ok "Created External ID user flow: ${FLOW_NAME}"
}

write_outputs() {
  cat > "$OUTPUT_FILE" <<EOF
# Generated by $(basename "$0") on $(date -u +%Y-%m-%dT%H:%M:%SZ)
export ENTRA_ENV_PREFIX='${ENV_PREFIX}'
export AZURE_TENANT_ID='${TENANT_ID}'
export AZURE_SUBSCRIPTION_ID='${SUBSCRIPTION_ID}'
export RESOURCE_GROUP='${RESOURCE_GROUP}'
export AZURE_CLIENT_ID='${GHA_APP_ID}'
export API_CLIENT_ID='${API_APP_ID}'
export API_APPLICATION_OBJECT_ID='${API_APP_OBJECT_ID}'
export API_SERVICE_PRINCIPAL_OBJECT_ID='${API_SP_OBJECT_ID}'
export API_IDENTIFIER_URI='${API_IDENTIFIER_URI}'
export API_SCOPE_ID='${API_SCOPE_ID}'
export API_SCOPE_VALUE='${API_SCOPE_VALUE}'
export WEB_CLIENT_ID='${WEB_APP_ID}'
export WEB_APPLICATION_OBJECT_ID='${WEB_APP_OBJECT_ID}'
export WEB_SERVICE_PRINCIPAL_OBJECT_ID='${WEB_SP_OBJECT_ID}'
export GITHUB_ACTIONS_CLIENT_ID='${GHA_APP_ID}'
export GITHUB_ACTIONS_APPLICATION_OBJECT_ID='${GHA_APP_OBJECT_ID}'
export GITHUB_ACTIONS_SERVICE_PRINCIPAL_OBJECT_ID='${GHA_SP_OBJECT_ID}'
export EXTERNAL_ID_USER_FLOW='${FLOW_NAME}'
export GITHUB_OIDC_ORG='${GITHUB_ORG}'
export GITHUB_OIDC_REPOS='${GITHUB_REPO_LIST}'
export TF_VAR_tenant_id='${TENANT_ID}'
export TF_VAR_api_client_id='${API_APP_ID}'
export TF_VAR_api_identifier_uri='${API_IDENTIFIER_URI}'
export TF_VAR_api_scope_value='${API_SCOPE_VALUE}'
export TF_VAR_web_client_id='${WEB_APP_ID}'
export TF_VAR_github_actions_client_id='${GHA_APP_ID}'
EOF
  ok "Wrote outputs to ${OUTPUT_FILE}"
}

need_cmd az
need_cmd awk
need_cmd sed
need_cmd tr

az account show --query id -o tsv --only-show-errors >/dev/null 2>&1 || die "Run 'az login' first"

ENV_PREFIX="${1:-wordgame-dev}"
: "${ENV_PREFIX:?environment prefix is required}"

RESOURCE_GROUP="${RESOURCE_GROUP:-${ENV_PREFIX}-rg}"
: "${RESOURCE_GROUP:?RESOURCE_GROUP is required}"

API_APP_NAME="${API_APP_NAME:-${ENV_PREFIX}-api}"
WEB_APP_NAME="${WEB_APP_NAME:-${ENV_PREFIX}-web}"
GHA_APP_NAME="${GHA_APP_NAME:-${ENV_PREFIX}-gha}"
WAF_APP_NAME="${WAF_APP_NAME:-word-game-waf}"
API_SCOPE_VALUE="${API_SCOPE_VALUE:-Games.Play}"
API_SCOPE_ID="${API_SCOPE_ID:-}"
API_IDENTIFIER_URI=""
FLOW_NAME="${FLOW_NAME:-B2C_1A_${ENV_PREFIX//-/_}_signup_signin}"
GITHUB_ORG="${GITHUB_ORG:-hoopdad}"
GITHUB_REPOS=(
  word-game-web
  word-game-api
  word-game-agent
  word-game-waf
  word-game-infra
)
GITHUB_REPO_LIST="${GITHUB_ORG}/word-game-web ${GITHUB_ORG}/word-game-api ${GITHUB_ORG}/word-game-agent ${GITHUB_ORG}/word-game-waf ${GITHUB_ORG}/word-game-infra"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-${SCRIPT_DIR}/setup-entra-${ENV_PREFIX}.env}"

TENANT_ID="$(az account show --query tenantId -o tsv --only-show-errors)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv --only-show-errors)"
: "${TENANT_ID:?unable to determine tenant id from az account show}"
: "${SUBSCRIPTION_ID:?unable to determine subscription id from az account show}"

RESOURCE_GROUP_ID="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv --only-show-errors)"
: "${RESOURCE_GROUP_ID:?resource group ${RESOURCE_GROUP} was not found}"

info "Using tenant ${TENANT_ID} and subscription ${SUBSCRIPTION_ID}"
info "Ensuring Entra resources for prefix ${ENV_PREFIX}"

API_APP_ID="$(ensure_app "$API_APP_NAME" 'AzureADMyOrg')"
API_APP_OBJECT_ID="$(az ad app show --id "$API_APP_ID" --query id -o tsv --only-show-errors)"
if [ -z "${API_SCOPE_ID:-}" ]; then
  API_SCOPE_ID="$(
    az ad app show \
      --id "$API_APP_ID" \
      --query "api.oauth2PermissionScopes[?value=='${API_SCOPE_VALUE}'].id | [0]" \
      -o tsv \
      --only-show-errors
  )"
fi
[ "${API_SCOPE_ID:-}" = "None" ] && API_SCOPE_ID=""
[ -n "${API_SCOPE_ID:-}" ] || API_SCOPE_ID="$(new_uuid)"
API_IDENTIFIER_URI="api://${API_APP_ID}"

API_PATCH_BODY="$(cat <<EOF
{"identifierUris":["${API_IDENTIFIER_URI}"],"signInAudience":"AzureADMyOrg","api":{"knownClientApplications":["04b07795-8ddb-461a-bbee-02f9e1bf7b46"],"requestedAccessTokenVersion":2,"oauth2PermissionScopes":[{"id":"${API_SCOPE_ID}","adminConsentDisplayName":"Play Word Game","adminConsentDescription":"Allows the app to call the Word Game API.","userConsentDisplayName":"Play Word Game","userConsentDescription":"Allows this app to call the Word Game API on your behalf.","value":"${API_SCOPE_VALUE}","type":"User","isEnabled":true}]}}
EOF
)"
graph_patch_application "$API_APP_OBJECT_ID" "$API_PATCH_BODY" "$API_APP_NAME"

API_SP_OBJECT_ID="$(ensure_service_principal "$API_APP_ID")"

WEB_APP_ID="$(ensure_app "$WEB_APP_NAME" 'AzureADandPersonalMicrosoftAccount')"
WEB_APP_OBJECT_ID="$(az ad app show --id "$WEB_APP_ID" --query id -o tsv --only-show-errors)"
WEB_PATCH_BODY="$(cat <<EOF
{"signInAudience":"AzureADandPersonalMicrosoftAccount","isFallbackPublicClient":true,"api":{"requestedAccessTokenVersion":2},"spa":{"redirectUris":$(build_spa_redirects_json)},"publicClient":{"redirectUris":$(build_public_client_redirects_json)},"requiredResourceAccess":[{"resourceAppId":"${API_APP_ID}","resourceAccess":[{"id":"${API_SCOPE_ID}","type":"Scope"}]}]}
EOF
)"
graph_patch_application "$WEB_APP_OBJECT_ID" "$WEB_PATCH_BODY" "$WEB_APP_NAME"
WEB_SP_OBJECT_ID="$(ensure_service_principal "$WEB_APP_ID")"

GHA_APP_ID="$(ensure_app "$GHA_APP_NAME" 'AzureADMyOrg')"
GHA_APP_OBJECT_ID="$(az ad app show --id "$GHA_APP_ID" --query id -o tsv --only-show-errors)"
GHA_SP_OBJECT_ID="$(ensure_service_principal "$GHA_APP_ID")"

for repo_name in "${GITHUB_REPOS[@]}"; do
  ensure_federated_credential \
    "$GHA_APP_ID" \
    "${ENV_PREFIX}-${repo_name}-main" \
    "repo:${GITHUB_ORG}/${repo_name}:ref:refs/heads/main" \
    "OIDC trust for ${GITHUB_ORG}/${repo_name} main branch"

  ensure_federated_credential \
    "$GHA_APP_ID" \
    "${ENV_PREFIX}-${repo_name}-pr" \
    "repo:${GITHUB_ORG}/${repo_name}:pull_request" \
    "OIDC trust for ${GITHUB_ORG}/${repo_name} pull requests"
done

ensure_contributor_role_assignment "$GHA_SP_OBJECT_ID"
ensure_external_id_user_flow
write_outputs

cat <<EOF

API_CLIENT_ID=${API_APP_ID}
WEB_CLIENT_ID=${WEB_APP_ID}
GITHUB_ACTIONS_CLIENT_ID=${GHA_APP_ID}
API_IDENTIFIER_URI=${API_IDENTIFIER_URI}
API_SCOPE_VALUE=${API_SCOPE_VALUE}
OUTPUT_FILE=${OUTPUT_FILE}
EOF

ok "Entra setup complete"
