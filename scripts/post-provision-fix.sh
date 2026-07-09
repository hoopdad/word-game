#!/usr/bin/env bash
# post-provision-fix.sh — reconcile two runtime dependencies the base Terraform leaves open when
# no hub DNS zone IDs / Foundry data-role are supplied (both additive; no Terraform drift):
#   1. Cosmos private DNS: create privatelink.documents.azure.com, link the spoke VNet, and attach a
#      dns-zone-group to the existing Cosmos private endpoint so the FQDN resolves to the PE IP.
#   2. Foundry data-plane access: grant the app's UAMI "Cognitive Services User" on the Foundry acct.
# Idempotent. Run AFTER `terraform apply` (PE + UAMI + Foundry must exist); restart api/agent after.
set -euo pipefail
info() { printf '[postfix] %s\n' "$*"; }

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TF_OUT="$HARNESS_DIR/.azure/tf-outputs.json"
[[ -s "$TF_OUT" ]] || { echo "[postfix][error] missing $TF_OUT (run azd-deploy.sh first)"; exit 2; }
tf() { jq -r ".${1}.value // empty" "$TF_OUT"; }

RG="$(tf resource_group_name)"
VNET_ID="$(tf vnet_id)"
UAMI_PRINCIPAL_ID="$(tf uami_principal_id)"
COSMOS_ENDPOINT="$(tf cosmos_endpoint)"
[[ -n "$RG" ]] || { echo "[postfix][error] no resource group in outputs"; exit 2; }

# ── 1. Cosmos private DNS ─────────────────────────────────────────────────────
ZONE="privatelink.documents.azure.com"
info "ensuring private DNS zone $ZONE in $RG"
az network private-dns zone show -g "$RG" -n "$ZONE" >/dev/null 2>&1 \
  || az network private-dns zone create -g "$RG" -n "$ZONE" >/dev/null
az network private-dns link vnet show -g "$RG" -z "$ZONE" -n vnet-link >/dev/null 2>&1 \
  || az network private-dns link vnet create -g "$RG" -z "$ZONE" -n vnet-link \
       --virtual-network "$VNET_ID" --registration-enabled false >/dev/null
PE_NAME="$(az network private-endpoint list -g "$RG" --query "[?contains(name,'cosmos')].name | [0]" -o tsv 2>/dev/null || true)"
if [[ -n "$PE_NAME" ]]; then
  info "attaching dns-zone-group to Cosmos PE $PE_NAME"
  az network private-endpoint dns-zone-group show -g "$RG" --endpoint-name "$PE_NAME" -n cosmos-zg >/dev/null 2>&1 \
    || az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name "$PE_NAME" -n cosmos-zg \
         --private-dns-zone "$ZONE" --zone-name documents >/dev/null
else
  info "⚠️  no cosmos private endpoint found — skipping zone-group"
fi

# ── 2. Foundry data-plane role for the UAMI ───────────────────────────────────
FOUNDRY_ID="$(az cognitiveservices account list -g "$RG" --query "[?kind=='AIServices'].id | [0]" -o tsv 2>/dev/null || true)"
if [[ -n "$FOUNDRY_ID" && -n "$UAMI_PRINCIPAL_ID" ]]; then
  info "granting 'Cognitive Services User' to UAMI on Foundry"
  az role assignment create --assignee-object-id "$UAMI_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Cognitive Services User" --scope "$FOUNDRY_ID" >/dev/null 2>&1 \
    || info "Foundry role may already exist"
else
  info "⚠️  Foundry account or UAMI principal not found — skipping role grant"
fi

info "done — restart api/agent revisions so they pick up Cosmos DNS + Foundry access"
