#!/usr/bin/env bash
# bootstrap-tfstate.sh — idempotently create the Terraform remote-state backend
# (resource group + storage account + blob container) in the spoke subscription.
#
# Required env:
#   TF_STATE_SA         globally-unique storage account name (3-24 lowercase/numbers)
# Optional env:
#   TF_STATE_RG         default: mikeo-lab-tfstate-rg
#   TF_STATE_CONTAINER  default: tfstate
#   AZURE_LOCATION      default: centralus
set -euo pipefail

RG="${TF_STATE_RG:-mikeo-lab-tfstate-rg}"
SA="${TF_STATE_SA:?set TF_STATE_SA to a globally-unique storage account name}"
CONTAINER="${TF_STATE_CONTAINER:-tfstate}"
LOCATION="${AZURE_LOCATION:-centralus}"

echo "Ensuring resource group ${RG} (${LOCATION})..."
az group create --name "$RG" --location "$LOCATION" --output none

if ! az storage account show --name "$SA" --resource-group "$RG" --output none 2>/dev/null; then
  echo "Creating storage account ${SA}..."
  az storage account create \
    --name "$SA" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --output none
else
  echo "Storage account ${SA} already exists."
fi

# Ensure public network access is enabled (data plane needed from GitHub-hosted runners).
az storage account update \
  --name "$SA" \
  --resource-group "$RG" \
  --public-network-access Enabled \
  --output none

echo "Ensuring container ${CONTAINER}..."
# Prefer Entra auth; some subscriptions block key-based auth by policy.
if az storage container create \
  --name "$CONTAINER" \
  --account-name "$SA" \
  --auth-mode login \
  --output none; then
  :
else
  echo "Entra auth failed; falling back to key auth for container creation..."
  SA_KEY="$(az storage account keys list --account-name "$SA" --resource-group "$RG" --query '[0].value' --output tsv)"
  az storage container create \
    --name "$CONTAINER" \
    --account-name "$SA" \
    --account-key "$SA_KEY" \
    --output none
fi

echo "Terraform state backend ready: rg=${RG} sa=${SA} container=${CONTAINER}"
