#!/usr/bin/env bash
# azd-deploy.sh — provision infra (terraform) + build images (az acr build) + deploy the four
# Container Apps (agent, api, web, waf) onto the word-game Container Apps Environment.
#
# Usage:  scripts/azd-deploy.sh [all|api|agent|web|waf]     (default: all)
# Env:
#   SKIP_PROVISION=1   skip terraform apply (reuse existing infra + .azure/tf-outputs.json)
#   IMAGE_TAG=<tag>    override image tag (default: harness short SHA, or timestamp if dirty)
#
# Prereqs: az login (correct subscription/tenant), VPN for private endpoints, jq, terraform.
#          scripts/setup-entra.sh must have been run (.azure/entra.json present).
set -euo pipefail

info() { printf '[deploy] %s\n' "$*"; }
die()  { printf '[deploy][error] %s\n' "$*" >&2; exit 1; }

TARGET="${1:-all}"
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
INFRA_DIR="$(cd "$HARNESS_DIR/../word-game-infra" && pwd)"
WEB_DIR="$(cd "$HARNESS_DIR/../word-game-web" && pwd)"
API_DIR="$(cd "$HARNESS_DIR/../word-game-api" && pwd)"
AGENT_DIR="$(cd "$HARNESS_DIR/../word-game-agent" && pwd)"
WAF_DIR="$(cd "$HARNESS_DIR/../word-game-waf" && pwd)"
AZURE_DIR="$HARNESS_DIR/.azure"
TF_OUT="$AZURE_DIR/tf-outputs.json"
ENTRA_JSON="$AZURE_DIR/entra.json"
mkdir -p "$AZURE_DIR"

for c in az jq terraform; do command -v "$c" >/dev/null || die "$c is required"; done
should() { [[ "$TARGET" == "all" || "$TARGET" == "$1" ]]; }

# Image tag: harness HEAD short SHA keeps deploys traceable; append -dirty timestamp if uncommitted
# so re-deploying the same commit still produces a fresh revision (see repo memory).
if [[ -n "${IMAGE_TAG:-}" ]]; then
  TAG="$IMAGE_TAG"
else
  SHA="$(git -C "$HARNESS_DIR" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  if [[ -n "$(git -C "$HARNESS_DIR" status --porcelain 2>/dev/null)" ]]; then
    TAG="${SHA}-$(date +%Y%m%d%H%M%S)"
  else
    TAG="$SHA"
  fi
fi
info "image tag: $TAG   target: $TARGET"

# ── 1. Provision infra ────────────────────────────────────────────────────────
if [[ "${SKIP_PROVISION:-0}" != "1" ]]; then
  info "terraform apply in $INFRA_DIR"
  ( cd "$INFRA_DIR" && terraform init -input=false >/dev/null && terraform apply -auto-approve -input=false )
fi
[[ -s "$TF_OUT" ]] || ( cd "$INFRA_DIR" && terraform output -json > "$TF_OUT" )
( cd "$INFRA_DIR" && terraform output -json > "$TF_OUT" )

tf() { jq -r ".${1}.value // empty" "$TF_OUT"; }
RG="$(tf resource_group_name)"
ACR_LOGIN="$(tf acr_login_server)"
ACR_NAME="${ACR_LOGIN%%.*}"
CAE_NAME="$(tf cae_name)"
COSMOS_ENDPOINT="$(tf cosmos_endpoint)"
COSMOS_DB="$(tf cosmos_database_name)"
FOUNDRY_ENDPOINT="$(tf foundry_endpoint)"
MODEL_NAME="$(tf model_deployment_name)"
UAMI_ID="$(tf uami_id)"
UAMI_CLIENT_ID="$(tf uami_client_id)"
LOCATION="$(tf location)"
[[ -n "$RG" && -n "$ACR_NAME" && -n "$CAE_NAME" ]] || die "terraform outputs incomplete in $TF_OUT"

[[ -f "$ENTRA_JSON" ]] || die "missing $ENTRA_JSON — run scripts/setup-entra.sh first"
TENANT_ID="$(jq -r .tenant_id "$ENTRA_JSON")"
API_CLIENT_ID="$(jq -r .api_client_id "$ENTRA_JSON")"
SPA_CLIENT_ID="$(jq -r .spa_client_id "$ENTRA_JSON")"
ENTRA_ISSUER="${ENTRA_ISSUER:-https://login.microsoftonline.com/${TENANT_ID}/v2.0}"

info "rg=$RG acr=$ACR_NAME cae=$CAE_NAME cosmos_db=$COSMOS_DB model=$MODEL_NAME"

# ── helpers ───────────────────────────────────────────────────────────────────
acr_build() { # <image> <context>
  info "az acr build $1 (context $2)"
  az acr build --registry "$ACR_NAME" --image "$1:$TAG" "$2" >/dev/null
}

app_exists() { az containerapp show -n "$1" -g "$RG" >/dev/null 2>&1; }

app_fqdn() { az containerapp show -n "$1" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null; }

# deploy_app <name> <image> <targetPort> <external:true|false> [env KEY=VAL ...]
deploy_app() {
  local name="$1" image="$2" port="$3" external="$4"; shift 4
  local envs=("$@")
  local itype; itype="$([[ "$external" == "true" ]] && echo external || echo internal)"
  if app_exists "$name"; then
    info "updating container app $name"
    if [[ ${#envs[@]} -gt 0 ]]; then
      az containerapp update -n "$name" -g "$RG" --image "$ACR_LOGIN/$image:$TAG" \
        --set-env-vars "${envs[@]}" >/dev/null
    else
      az containerapp update -n "$name" -g "$RG" --image "$ACR_LOGIN/$image:$TAG" >/dev/null
    fi
    az containerapp ingress enable -n "$name" -g "$RG" --type "$itype" \
      --target-port "$port" --transport auto --allow-insecure >/dev/null 2>&1 || true
  else
    info "creating container app $name"
    if [[ ${#envs[@]} -gt 0 ]]; then
      az containerapp create -n "$name" -g "$RG" --environment "$CAE_NAME" \
        --image "$ACR_LOGIN/$image:$TAG" \
        --registry-server "$ACR_LOGIN" --registry-identity "$UAMI_ID" --user-assigned "$UAMI_ID" \
        --min-replicas 1 --max-replicas 3 --ingress "$itype" --target-port "$port" --transport auto \
        --env-vars "${envs[@]}" >/dev/null
    else
      az containerapp create -n "$name" -g "$RG" --environment "$CAE_NAME" \
        --image "$ACR_LOGIN/$image:$TAG" \
        --registry-server "$ACR_LOGIN" --registry-identity "$UAMI_ID" --user-assigned "$UAMI_ID" \
        --min-replicas 1 --max-replicas 3 --ingress "$itype" --target-port "$port" --transport auto \
        >/dev/null
    fi
    # internal apps: allow plain-HTTP intra-CAE calls so the WAF can proxy over http://<name>.
    if [[ "$external" != "true" ]]; then
      az containerapp ingress enable -n "$name" -g "$RG" --type internal \
        --target-port "$port" --transport auto --allow-insecure >/dev/null 2>&1 || true
    fi
  fi
}

wait_running() { # <name>
  local name="$1" timeout=180 el=0 rev state
  rev="$(az containerapp show -n "$name" -g "$RG" --query properties.latestRevisionName -o tsv 2>/dev/null || true)"
  [[ -z "$rev" ]] && { info "$name: no revision yet"; return 0; }
  while [[ $el -lt $timeout ]]; do
    state="$(az containerapp revision show -n "$name" -g "$RG" --revision "$rev" \
      --query properties.runningState -o tsv 2>/dev/null || echo Unknown)"
    case "$state" in
      Running|RunningAtMaxScale) info "✅ $name running"; return 0 ;;
      Failed|Degraded)          die "❌ $name revision $rev state=$state" ;;
      *) sleep 10; el=$((el+10)) ;;
    esac
  done
  info "⚠️  $name still $state after ${timeout}s (continuing)"
}

# ── 2. Build + deploy in dependency order: agent → api → web → waf ────────────
# AGENT
if should agent; then
  acr_build word-game-agent "$AGENT_DIR"
  deploy_app word-game-agent word-game-agent 8000 false \
    "FOUNDRY_PROJECT_ENDPOINT=$FOUNDRY_ENDPOINT" "FOUNDRY_MODEL=$MODEL_NAME" \
    "AZURE_TENANT_ID=$TENANT_ID" "AZURE_CLIENT_ID=$UAMI_CLIENT_ID" "AZURE_REGION=$LOCATION"
  wait_running word-game-agent
fi

# API (needs agent reachable in-CAE)
if should api; then
  acr_build word-game-api "$API_DIR"
  deploy_app word-game-api word-game-api 8000 false \
    "WORD_GAME_COSMOS_ENDPOINT=$COSMOS_ENDPOINT" "WORD_GAME_COSMOS_DATABASE=$COSMOS_DB" \
    "WORD_GAME_FOUNDRY_ENDPOINT=$FOUNDRY_ENDPOINT" \
    "WORD_GAME_AZURE_TENANT_ID=$TENANT_ID" "WORD_GAME_AZURE_CLIENT_ID=$UAMI_CLIENT_ID" \
    "AZURE_CLIENT_ID=$UAMI_CLIENT_ID" \
    "WORD_GAME_ENTRA_ISSUER=$ENTRA_ISSUER" "WORD_GAME_ENTRA_AUDIENCE=$API_CLIENT_ID" \
    "WORD_GAME_AGENT_ENDPOINT=http://word-game-agent"
  wait_running word-game-api
fi

# WEB (VITE_* baked at build time; no runtime env needed)
if should web; then
  info "az acr build word-game-web (VITE build args)"
  az acr build --registry "$ACR_NAME" --image "word-game-web:$TAG" \
    --build-arg VITE_MSAL_CLIENT_ID="$SPA_CLIENT_ID" \
    --build-arg VITE_MSAL_API_CLIENT_ID="$API_CLIENT_ID" \
    "$WEB_DIR" >/dev/null
  deploy_app word-game-web word-game-web 80 false
  wait_running word-game-web
fi

# WAF (public entry; needs web/api/agent reachable). min-replicas=1 enforced by deploy_app.
if should waf; then
  acr_build word-game-waf "$WAF_DIR"
  deploy_app word-game-waf word-game-waf 8080 true \
    "BACKEND_WEB=word-game-web:80" "BACKEND_API=word-game-api:80" "BACKEND_AGENT=word-game-agent:80" \
    "PORT=8080" "MODSEC_RULE_ENGINE=On" "PARANOIA=1"
  wait_running word-game-waf
fi

# ── 3. Finalise Entra redirect URIs + API CORS with the live WAF FQDN ─────────
WAF_FQDN="$(app_fqdn word-game-waf || true)"
if [[ -n "$WAF_FQDN" ]]; then
  WAF_URL="https://$WAF_FQDN"
  info "WAF FQDN: $WAF_URL"
  info "updating SPA redirect URIs (via Graph)"
  SPA_OBJ_ID="$(az ad app show --id "$SPA_CLIENT_ID" --query id -o tsv 2>/dev/null || true)"
  if [[ -n "$SPA_OBJ_ID" ]]; then
    az rest --method PATCH \
      --uri "https://graph.microsoft.com/v1.0/applications/$SPA_OBJ_ID" \
      --headers "Content-Type=application/json" \
      --body "{\"spa\":{\"redirectUris\":[\"$WAF_URL/welcome\",\"$WAF_URL/\",\"http://localhost:5173/welcome\"]}}" \
      >/dev/null 2>&1 || info "could not update SPA redirect URIs (check permissions)"
  fi
  if should api || should all; then
    info "setting API allowed origins to $WAF_URL"
    az containerapp update -n word-game-api -g "$RG" \
      --set-env-vars "WORD_GAME_ALLOWED_ORIGINS=[\"$WAF_URL\"]" >/dev/null 2>&1 || true
  fi
  # Persist deploy facts for verify + topology.
  jq -n --arg waf "$WAF_URL" --arg rg "$RG" --arg tag "$TAG" \
        --arg spa "$SPA_CLIENT_ID" --arg api "$API_CLIENT_ID" \
    '{waf_url:$waf, resource_group:$rg, image_tag:$tag, spa_client_id:$spa, api_client_id:$api}' \
    > "$AZURE_DIR/deploy.json"
  info "wrote $AZURE_DIR/deploy.json"
fi

info "✅ deploy complete (target=$TARGET, tag=$TAG)"
[[ -n "${WAF_FQDN:-}" ]] && info "Open the app at: https://$WAF_FQDN  (requires VNet/VPN access)"
info "Run scripts/verify-deploy.sh to smoke-test."
