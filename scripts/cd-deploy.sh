#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/cd-deploy.sh --targets <csv|all> [--image-tag <tag>]
Example: scripts/cd-deploy.sh --targets web,api,agent,waf
EOF
}

log() {
  echo "[cd-deploy] $*"
}

die() {
  echo "[cd-deploy] error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

target_enabled() {
  local needle="$1"
  [[ ",${TARGETS}," == *",${needle},"* ]]
}

TARGETS=""
IMAGE_TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets)
      TARGETS="${2:-}"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="${2:-}"
      shift 2
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

[[ -n "$TARGETS" ]] || { usage; die "--targets is required"; }

if [[ "$TARGETS" == "all" ]]; then
  TARGETS="web,api,agent,waf"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

require_cmd az
require_cmd jq

if [[ -z "$IMAGE_TAG" ]]; then
  require_cmd git
  IMAGE_TAG="$(git rev-parse --short HEAD)"
  [[ -n "$IMAGE_TAG" ]] || die "unable to derive default image tag from git HEAD"
  log "Defaulting image tag to ${IMAGE_TAG}"
fi

RESOURCE_GROUP="${RESOURCE_GROUP:-mikeo-lab-infra-rg}"
WEB_APP_NAME="${WEB_APP_NAME:-ca-web-mikeo-lab-infra}"
API_APP_NAME="${API_APP_NAME:-ca-api-mikeo-lab-infra}"
AGENT_APP_NAME="${AGENT_APP_NAME:-ca-agent-mikeo-lab-infra}"
WAF_APP_NAME="${WAF_APP_NAME:-ca-waf-mikeo-lab-infra}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

log "Ensuring Container Apps extension"
az extension add --name containerapp --upgrade --output none

if [[ -n "${ACR_NAME:-}" ]]; then
  log "Using configured ACR_NAME=${ACR_NAME}"
else
  ACR_NAME="$(az acr list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)"
fi
[[ "$ACR_NAME" =~ ^[a-zA-Z0-9]{5,50}$ ]] || die "invalid ACR name: ${ACR_NAME}"

ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
[[ "$ACR_LOGIN_SERVER" == *.azurecr.io ]] || die "invalid ACR login server: ${ACR_LOGIN_SERVER}"

require_cmd docker

log "Logging in to ACR via Azure identity (az acr login)"
az acr login --name "$ACR_NAME" --expose-token \
  | jq -r '.accessToken' \
  | docker login --username "00000000-0000-0000-0000-000000000000" \
      --password-stdin "$ACR_LOGIN_SERVER" 2>&1 \
  | grep -v "WARNING\|username" || true

if target_enabled web; then
  log "Building (${BUILD_PLATFORM}) and pushing web:${IMAGE_TAG}"
  docker build \
    --platform "${BUILD_PLATFORM}" \
    --file apps/web/Dockerfile \
    --build-arg VITE_ENTRA_CLIENT_ID="${VITE_ENTRA_CLIENT_ID:-}" \
    --build-arg VITE_ENTRA_AUTHORITY="${VITE_ENTRA_AUTHORITY:-}" \
    --build-arg VITE_ENTRA_REDIRECT_URI="${VITE_ENTRA_REDIRECT_URI:-}" \
    --build-arg VITE_ENTRA_POST_LOGOUT_REDIRECT_URI="${VITE_ENTRA_POST_LOGOUT_REDIRECT_URI:-}" \
    --build-arg VITE_ENTRA_SCOPES="${VITE_ENTRA_SCOPES:-}" \
    --tag "${ACR_LOGIN_SERVER}/web:${IMAGE_TAG}" \
    .
  docker push "${ACR_LOGIN_SERVER}/web:${IMAGE_TAG}"
  az containerapp update --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --image "${ACR_LOGIN_SERVER}/web:${IMAGE_TAG}" --revision-suffix "$(date +%s)" --output none
fi

if target_enabled api; then
  log "Building (${BUILD_PLATFORM}) and pushing api:${IMAGE_TAG}"
  docker build --platform "${BUILD_PLATFORM}" --file apps/api/Dockerfile --tag "${ACR_LOGIN_SERVER}/api:${IMAGE_TAG}" .
  docker push "${ACR_LOGIN_SERVER}/api:${IMAGE_TAG}"
  az containerapp update \
    --name "$API_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --image "${ACR_LOGIN_SERVER}/api:${IMAGE_TAG}" \
    --set-env-vars \
    ENTRA_JWT_ISSUER="${ENTRA_JWT_ISSUER:-}" \
    ENTRA_JWT_AUDIENCE="${ENTRA_JWT_AUDIENCE:-}" \
    ENTRA_REQUIRED_SCOPE="${ENTRA_REQUIRED_SCOPE:-}" \
    ENTRA_JWKS_URI="${ENTRA_JWKS_URI:-}" \
    --revision-suffix "$(date +%s)" \
    --output none
fi

if target_enabled agent; then
  log "Building (${BUILD_PLATFORM}) and pushing agent:${IMAGE_TAG}"
  docker build --platform "${BUILD_PLATFORM}" --file apps/agent/Dockerfile --tag "${ACR_LOGIN_SERVER}/agent:${IMAGE_TAG}" .
  docker push "${ACR_LOGIN_SERVER}/agent:${IMAGE_TAG}"
  az containerapp update --name "$AGENT_APP_NAME" --resource-group "$RESOURCE_GROUP" --image "${ACR_LOGIN_SERVER}/agent:${IMAGE_TAG}" --revision-suffix "$(date +%s)" --output none
fi

if target_enabled waf; then
  log "Building (${BUILD_PLATFORM}) and pushing waf:${IMAGE_TAG}"
  docker build --platform "${BUILD_PLATFORM}" --file apps/waf/Dockerfile --tag "${ACR_LOGIN_SERVER}/waf:${IMAGE_TAG}" apps/waf
  docker push "${ACR_LOGIN_SERVER}/waf:${IMAGE_TAG}"
  az containerapp update --name "$WAF_APP_NAME" --resource-group "$RESOURCE_GROUP" --image "${ACR_LOGIN_SERVER}/waf:${IMAGE_TAG}" --revision-suffix "$(date +%s)" --output none
fi

log "Deployment targets (${TARGETS}) completed with image tag ${IMAGE_TAG}"
