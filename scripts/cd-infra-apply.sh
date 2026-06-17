#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/cd-infra-apply.sh [--github-output <path>] [--skip-provider-register]
EOF
}

log() {
  echo "[cd-infra] $*"
}

die() {
  echo "[cd-infra] error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

GITHUB_OUTPUT_PATH=""
REGISTER_PROVIDERS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-output)
      GITHUB_OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --skip-provider-register)
      REGISTER_PROVIDERS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

require_cmd az
require_cmd terraform
require_cmd jq

: "${TF_STATE_SA:?set TF_STATE_SA to the Terraform state storage account name}"

TF_STATE_RG="${TF_STATE_RG:-mikeo-lab-tfstate-rg}"
TF_STATE_CONTAINER="${TF_STATE_CONTAINER:-tfstate}"
TF_STATE_KEY="${TF_STATE_KEY:-wordgame-spoke.tfstate}"

if [[ "$REGISTER_PROVIDERS" -eq 1 ]]; then
  log "Registering required Azure resource providers"
  for ns in \
    Microsoft.App \
    Microsoft.Compute \
    Microsoft.ContainerRegistry \
    Microsoft.DocumentDB \
    Microsoft.Network \
    Microsoft.KeyVault \
    Microsoft.Storage \
    Microsoft.CognitiveServices \
    Microsoft.OperationalInsights
  do
    az provider register --namespace "$ns" --wait --output none
  done
fi

log "Ensuring Terraform backend"
scripts/bootstrap-tfstate.sh

log "Running Terraform init/validate/apply"
terraform -chdir=mcaps-infra init -input=false \
  -backend-config="resource_group_name=${TF_STATE_RG}" \
  -backend-config="storage_account_name=${TF_STATE_SA}" \
  -backend-config="container_name=${TF_STATE_CONTAINER}" \
  -backend-config="key=${TF_STATE_KEY}" \
  -backend-config="use_azuread_auth=true"
terraform -chdir=mcaps-infra validate

set +e
for BLOB_NAME in "tfstate/${TF_STATE_KEY}" "${TF_STATE_KEY}"; do
  az storage blob lease break \
    --account-name "${TF_STATE_SA}" \
    --container-name "${TF_STATE_CONTAINER}" \
    --blob-name "${BLOB_NAME}" \
    --auth-mode login \
    --output none
done
set -e
sleep 10

terraform -chdir=mcaps-infra apply -auto-approve -input=false

RESOURCE_GROUP="$(terraform -chdir=mcaps-infra output -raw resource_group_name)"
ACR_LOGIN_SERVER="$(terraform -chdir=mcaps-infra output -raw acr_login_server)"
WEB_APP_NAME="$(terraform -chdir=mcaps-infra output -json container_app_names | jq -r '.web')"
API_APP_NAME="$(terraform -chdir=mcaps-infra output -json container_app_names | jq -r '.api')"
AGENT_APP_NAME="$(terraform -chdir=mcaps-infra output -json container_app_names | jq -r '.agent')"
WAF_APP_NAME="$(terraform -chdir=mcaps-infra output -json container_app_names | jq -r '.waf')"

[[ "$ACR_LOGIN_SERVER" == *.azurecr.io ]] || die "invalid acr_login_server output: $ACR_LOGIN_SERVER"

for key in resource_group acr_login_server web_app_name api_app_name agent_app_name waf_app_name; do
  case "$key" in
    resource_group) value="$RESOURCE_GROUP" ;;
    acr_login_server) value="$ACR_LOGIN_SERVER" ;;
    web_app_name) value="$WEB_APP_NAME" ;;
    api_app_name) value="$API_APP_NAME" ;;
    agent_app_name) value="$AGENT_APP_NAME" ;;
    waf_app_name) value="$WAF_APP_NAME" ;;
  esac
  log "${key}=${value}"
  if [[ -n "$GITHUB_OUTPUT_PATH" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT_PATH"
  fi
done
