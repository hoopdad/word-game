#!/usr/bin/env bash
# reset-rg.sh — Destructively destroys rg-wordgame-dev and recreates via Terraform.
# Usage: ./scripts/reset-rg.sh [--yes] [--location centralus]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"

RG_NAME="${RG_NAME:-rg-wordgame-dev}"
LOCATION="${LOCATION:-centralus}"
AUTO_YES="${AUTO_YES:-false}"

for arg in "$@"; do
  case "$arg" in
    --yes) AUTO_YES=true ;;
    --location=*) LOCATION="${arg#*=}" ;;
  esac
done

echo ""
echo "⚠️  DESTRUCTIVE RESET — rg-wordgame-dev"
echo "   Resource group : ${RG_NAME}"
echo "   Location       : ${LOCATION}"
echo "   This will DELETE all resources and recreate from Terraform."
echo ""

if [[ "${AUTO_YES}" != "true" ]]; then
  read -r -p "Type 'yes' to confirm: " CONFIRM
  [[ "${CONFIRM}" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

echo ""
echo "── Step 1: Delete resource group ──────────────────────"
az group delete --name "${RG_NAME}" --yes --no-wait 2>/dev/null || true
echo "Deletion initiated (--no-wait). Polling until complete..."
until ! az group exists --name "${RG_NAME}" --output tsv 2>/dev/null | grep -q "true"; do
  printf '.'
  sleep 10
done
echo ""
echo "✓ Resource group deleted."

echo ""
echo "── Step 2: Register required resource providers ────────"
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.ContainerRegistry --wait
az provider register --namespace Microsoft.DocumentDB --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.KeyVault --wait
az provider register --namespace Microsoft.Storage --wait
echo "✓ Providers registered."

echo ""
echo "── Step 3: Terraform init + apply ──────────────────────"
cd "${INFRA_DIR}"
terraform init -input=false
terraform apply \
  -auto-approve \
  -input=false \
  -var="location=${LOCATION}" \
  -var="enable_role_assignments=false"
echo ""
echo "✓ Infrastructure recreated."
echo ""
terraform output
echo ""
echo "Next: deploy the custom WAF image (CI/CD deploy-waf or equivalent) so path-based routing is active."
