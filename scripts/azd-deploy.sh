#!/usr/bin/env bash
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
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
CAE_ID="$(read_output '.container_app_environment_ids.value.internal')"
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
info "  Container App Environment: $CAE_ID"
info "  Managed Identity Client ID: $MI_CLIENT_ID"
info "  Image Tag: $TAG"

ensure_containerapp_ingress() {
  local app_name="$1"
  local ingress_type="$2"
  local port="$3"

  az containerapp ingress update \
    --name "$app_name" \
    --resource-group "$RG" \
    --type "$ingress_type" \
    --target-port "$port" \
    --only-show-errors >/dev/null
}

deploy_service() {
  local service_name="$1"
  local service_dir="$2"
  local port="$3"
  local ingress_type="$4"
  shift 4

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
      --environment "$CAE_ID" \
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

deploy_service \
  api \
  "$API_DIR" \
  8000 \
  internal \
  "COSMOS_ENDPOINT=${COSMOS_ENDPOINT}" \
  "COSMOS_DATABASE_NAME=word-game" \
  "KEY_VAULT_URL=${KV_URI}"

deploy_service \
  agent \
  "$AGENT_DIR" \
  8000 \
  internal \
  "AZURE_FOUNDRY_URL=https://wordgamedevfoundry.cognitiveservices.azure.com/" \
  "KEY_VAULT_URL=${KV_URI}"

deploy_service \
  web \
  "$WEB_DIR" \
  80 \
  internal

API_FQDN="$(az containerapp show --name word-game-api --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"
AGENT_FQDN="$(az containerapp show --name word-game-agent --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"
WEB_FQDN="$(az containerapp show --name word-game-web --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"

deploy_service \
  waf \
  "$WAF_DIR" \
  443 \
  external \
  "API_UPSTREAM=https://${API_FQDN}" \
  "AGENT_UPSTREAM=https://${AGENT_FQDN}" \
  "WEB_UPSTREAM=https://${WEB_FQDN}"

WAF_FQDN="$(az containerapp show --name word-game-waf --resource-group "$RG" --query properties.configuration.ingress.fqdn -o tsv --only-show-errors)"

ok "Deployment complete"
info "WAF endpoint: https://${WAF_FQDN}"
