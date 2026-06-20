#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# Optional first argument selects a single service to deploy (default: all).
DEPLOY_TARGET="${1:-all}"
case "$DEPLOY_TARGET" in
  all|api|agent|web|waf) ;;
  *) die "Invalid deploy target '$DEPLOY_TARGET' (expected: all|api|agent|web|waf)" ;;
esac

should_deploy() {
  [ "$DEPLOY_TARGET" = "all" ] || [ "$DEPLOY_TARGET" = "$1" ]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_OUTPUT_FILE="$HARNESS_DIR/.azure/tf-outputs.json"

need_cmd az
need_cmd jq
need_cmd git

az account show >/dev/null 2>&1 || die "Not logged in to Azure. Run 'az login' first."
[ -f "$TF_OUTPUT_FILE" ] || die "Terraform outputs not found at $TF_OUTPUT_FILE. Run 'azd provision' or 'azd up' first."

read_output() {
  jq -er "$1" "$TF_OUTPUT_FILE"
}

RG="$(read_output '.resource_group_name.value')"
ACR_LOGIN_SERVER="$(read_output '.acr_login_server.value')"
ACR_NAME="${ACR_LOGIN_SERVER%%.*}"
CAE_EDGE_ID="$(read_output '.container_app_environment_ids.value.edge')"
MI_CLIENT_ID="$(read_output '.managed_identity_client_id.value')"
COSMOS_ENDPOINT="$(read_output '.cosmos_endpoint.value')"
KV_URI="$(read_output '.key_vault_uri.value')"

MI_RESOURCE_ID="$({
  az identity list \
    --resource-group "$RG" \
    --query "[?clientId=='${MI_CLIENT_ID}'].id | [0]" \
    -o tsv \
    --only-show-errors
} || true)"

[ -n "${MI_RESOURCE_ID:-}" ] && [ "$MI_RESOURCE_ID" != "None" ] || die "Unable to resolve the user-assigned managed identity resource ID for client ID $MI_CLIENT_ID in resource group $RG"

SHA="$(git -C "$HARNESS_DIR" rev-parse --short HEAD 2>/dev/null || true)"
TAG="${SHA:-latest}"

info "Deployment configuration"
info "  Resource Group: $RG"
info "  ACR: $ACR_LOGIN_SERVER"
info "  Container App Environment (edge): $CAE_EDGE_ID"
info "  Managed Identity Client ID: $MI_CLIENT_ID"
info "  Image Tag: $TAG"

ensure_containerapp_ingress() {
  local app_name="$1"
  local ingress_type="$2"
  local port="$3"

  local allow_insecure_flag=""
  if [ "$ingress_type" = "internal" ]; then
    allow_insecure_flag="--allow-insecure"
  fi

  az containerapp ingress update \
    --name "$app_name" \
    --resource-group "$RG" \
    --type "$ingress_type" \
    --target-port "$port" \
    $allow_insecure_flag \
    --only-show-errors >/dev/null
}

deploy_service() {
  local service_name="$1"
  local service_dir="$2"
  local port="$3"
  local ingress_type="$4"
  local cae_id="$5"
  shift 5

  [ -d "$service_dir" ] || die "Service directory not found: $service_dir"

  local app_name="word-game-${service_name}"
  local image_repo="word-game-${service_name}"
  local image_ref="${ACR_LOGIN_SERVER}/${image_repo}:${TAG}"
  local -a env_vars=("AZURE_CLIENT_ID=${MI_CLIENT_ID}")
  local env_var

  for env_var in "$@"; do
    env_vars+=("$env_var")
  done

  info "Building ${service_name} image in ACR"
  az acr build \
    --registry "$ACR_NAME" \
    --image "${image_repo}:${TAG}" \
    --image "${image_repo}:latest" \
    "$service_dir" \
    --no-logs \
    --only-show-errors

  if az containerapp show --name "$app_name" --resource-group "$RG" --query name -o tsv --only-show-errors >/dev/null 2>&1; then
    info "Updating ${app_name}"
    az containerapp update \
      --name "$app_name" \
      --resource-group "$RG" \
      --image "$image_ref" \
      --set-env-vars "${env_vars[@]}" \
      --only-show-errors >/dev/null
  else
    info "Creating ${app_name}"
    az containerapp create \
      --name "$app_name" \
      --resource-group "$RG" \
      --environment "$cae_id" \
      --image "$image_ref" \
      --target-port "$port" \
      --ingress "$ingress_type" \
      --min-replicas 0 \
      --max-replicas 3 \
      --user-assigned "$MI_RESOURCE_ID" \
      --registry-server "$ACR_LOGIN_SERVER" \
      --registry-identity "$MI_RESOURCE_ID" \
      --env-vars "${env_vars[@]}" \
      --cpu 0.25 \
      --memory 0.5Gi \
      --only-show-errors >/dev/null
  fi

  ensure_containerapp_ingress "$app_name" "$ingress_type" "$port"
  ok "${service_name} deployed"
}

API_DIR="$(cd "$HARNESS_DIR/../word-game-api" && pwd)"
AGENT_DIR="$(cd "$HARNESS_DIR/../word-game-agent" && pwd)"
WEB_DIR="$(cd "$HARNESS_DIR/../word-game-web" && pwd)"
WAF_DIR="$(cd "$HARNESS_DIR/../word-game-waf" && pwd)"

# Entra configuration for web SPA
ENTRA_WEB_CLIENT_ID="${ENTRA_WEB_CLIENT_ID:-b4d29652-ff30-43ea-90f6-830cc340f866}"
ENTRA_API_CLIENT_ID="${ENTRA_API_CLIENT_ID:-16f3fd41-cddd-44fb-a149-14314e62f7a8}"
ENTRA_TENANT_ID="${ENTRA_TENANT_ID:-d52a6857-5f44-4f8f-bcc8-420952d3225d}"
MSAL_AUTHORITY="https://login.microsoftonline.com/common"

if should_deploy api; then
deploy_service \
  api \
  "$API_DIR" \
  8000 \
  internal \
  "$CAE_EDGE_ID" \
  "COSMOS_ENDPOINT=${COSMOS_ENDPOINT}" \
  "COSMOS_DATABASE_NAME=word-game" \
  "KEY_VAULT_URL=${KV_URI}" \
  "OIDC_METADATA_URL=https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration" \
  "JWT_ISSUER=" \
  "JWT_AUDIENCE=${ENTRA_API_CLIENT_ID}" \
  "JWT_REQUIRED_SCOPE=access_as_user"
fi

if should_deploy agent; then
deploy_service \
  agent \
  "$AGENT_DIR" \
  8000 \
  internal \
  "$CAE_EDGE_ID" \
  "AZURE_FOUNDRY_URL=https://wordgamedevfoundry.cognitiveservices.azure.com/" \
  "KEY_VAULT_URL=${KV_URI}"
fi

if should_deploy web; then
# Resolve WAF FQDN for MSAL redirect URI (WAF app must exist from prior deploy)
WAF_FQDN="$(az containerapp show --name word-game-waf --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || true)"
if [ -z "${WAF_FQDN:-}" ]; then
  MSAL_REDIRECT_URI="http://localhost:3000/welcome"
  info "WAF not yet deployed; using localhost redirect URI for web build"
else
  MSAL_REDIRECT_URI="https://${WAF_FQDN}/welcome"
fi

# Build web with MSAL config injected at build time
info "Building web image in ACR (with MSAL build args)"
az acr build \
  --registry "$ACR_NAME" \
  --image "word-game-web:${TAG}" \
  --image "word-game-web:latest" \
  --build-arg "VITE_MSAL_CLIENT_ID=${ENTRA_WEB_CLIENT_ID}" \
  --build-arg "VITE_MSAL_AUTHORITY=${MSAL_AUTHORITY}" \
  --build-arg "VITE_MSAL_REDIRECT_URI=${MSAL_REDIRECT_URI}" \
  --build-arg "VITE_MSAL_API_CLIENT_ID=${ENTRA_API_CLIENT_ID}" \
  --build-arg "VITE_API_BASE_URL=/api" \
  --build-arg "VITE_WS_BASE_URL=" \
  "$WEB_DIR" \
  --no-logs \
  --only-show-errors

WEB_IMAGE_REF="${ACR_LOGIN_SERVER}/word-game-web:${TAG}"
WEB_APP_NAME="word-game-web"

if az containerapp show --name "$WEB_APP_NAME" --resource-group "$RG" --query name -o tsv --only-show-errors >/dev/null 2>&1; then
  info "Updating ${WEB_APP_NAME}"
  # min-replicas=1: web is the WAF-fronted public SPA; scale-to-zero causes
  # cold-start activation failures that leave the new revision unhealthy while
  # the old revision keeps serving a stale bundle.
  az containerapp update \
    --name "$WEB_APP_NAME" \
    --resource-group "$RG" \
    --image "$WEB_IMAGE_REF" \
    --min-replicas 1 \
    --max-replicas 3 \
    --set-env-vars "AZURE_CLIENT_ID=${MI_CLIENT_ID}" \
    --only-show-errors >/dev/null
else
  info "Creating ${WEB_APP_NAME}"
  az containerapp create \
    --name "$WEB_APP_NAME" \
    --resource-group "$RG" \
    --environment "$CAE_EDGE_ID" \
    --image "$WEB_IMAGE_REF" \
    --target-port 8080 \
    --ingress internal \
    --min-replicas 1 \
    --max-replicas 3 \
    --user-assigned "$MI_RESOURCE_ID" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-identity "$MI_RESOURCE_ID" \
    --env-vars "AZURE_CLIENT_ID=${MI_CLIENT_ID}" \
    --cpu 0.25 \
    --memory 0.5Gi \
    --only-show-errors >/dev/null
fi

ensure_containerapp_ingress "$WEB_APP_NAME" "internal" 8080

# Verify the new revision actually activates; a failed cold-start would otherwise
# leave an old revision serving a stale bundle while the deploy reports success.
WEB_LATEST_REV="$(az containerapp show --name "$WEB_APP_NAME" --resource-group "$RG" --query properties.latestRevisionName -o tsv --only-show-errors)"
WEB_WAIT=0
WEB_STATE=""
while [ "$WEB_WAIT" -lt 150 ]; do
  WEB_STATE="$(az containerapp revision show --name "$WEB_APP_NAME" --resource-group "$RG" --revision "$WEB_LATEST_REV" --query properties.runningState -o tsv --only-show-errors 2>/dev/null || echo Unknown)"
  case "$WEB_STATE" in
    Running) break ;;
    Failed|ActivationFailed) die "web revision $WEB_LATEST_REV failed to activate (state=$WEB_STATE)" ;;
    *) sleep 10; WEB_WAIT=$((WEB_WAIT + 10)) ;;
  esac
done
[ "$WEB_STATE" = "Running" ] || die "web revision $WEB_LATEST_REV did not reach Running (state=$WEB_STATE)"
ok "web deployed (revision $WEB_LATEST_REV Running)"
fi

if should_deploy waf; then
API_FQDN="$(az containerapp show --name word-game-api --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"
AGENT_FQDN="$(az containerapp show --name word-game-agent --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"
WEB_FQDN="$(az containerapp show --name word-game-web --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"
WAF_FQDN="$(az containerapp show --name word-game-waf --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || true)"

deploy_service \
  waf \
  "$WAF_DIR" \
  8080 \
  external \
  "$CAE_EDGE_ID" \
  "API_UPSTREAM=http://${API_FQDN}" \
  "AGENT_UPSTREAM=http://${AGENT_FQDN}" \
  "WEB_UPSTREAM=http://${WEB_FQDN}" \
  "CORS_ALLOWED_ORIGIN=https://${WAF_FQDN}"

# WAF is the public entry point — never scale to zero
az containerapp update --name word-game-waf --resource-group "$RG" --min-replicas 1 --only-show-errors -o none
fi

WAF_FQDN="$(az containerapp show --name word-game-waf --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors 2>/dev/null || true)"

ok "Deployment complete"
if [ -n "${WAF_FQDN:-}" ]; then info "WAF endpoint: https://${WAF_FQDN}"; fi

# ──────────────────────────────────────────────
# Post-deploy verification (only for full or waf deploys)
# ──────────────────────────────────────────────
if should_deploy waf && [ -n "${WAF_FQDN:-}" ]; then
  echo ""
  info "Running post-deploy verification..."
  "$SCRIPT_DIR/check-msal-config.sh" || true
  echo ""
  "$SCRIPT_DIR/verify-deploy.sh" "$WAF_FQDN" || true
fi
