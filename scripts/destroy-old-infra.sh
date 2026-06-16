#!/usr/bin/env bash
# destroy-old-infra.sh — tear down the legacy standalone stack.
#
# The legacy infra/ stack lives entirely in resource group rg-wordgame-dev and
# used ephemeral local Terraform state (re-imported every CD run), so the most
# reliable teardown is a resource-group delete rather than `terraform destroy`.
#
# Usage:
#   ./scripts/destroy-old-infra.sh            # interactive confirm
#   ./scripts/destroy-old-infra.sh --yes      # no prompt (CI)
#   ./scripts/destroy-old-infra.sh --rg=rg-x  # override resource group
set -euo pipefail

RG="${OLD_RG:-rg-wordgame-dev}"
AUTO_YES="${AUTO_YES:-false}"

for arg in "$@"; do
  case "$arg" in
    --yes) AUTO_YES=true ;;
    --rg=*) RG="${arg#*=}" ;;
  esac
done

# Hard guard: never allow this teardown tool to delete the new spoke stack, the
# Terraform state account's RG, or the hub RG, even if passed explicitly.
case "$RG" in
  mikeo-lab-infra-rg | mikeo-lab-tfstate-rg | mikeo-lab-rg)
    echo "Refusing to delete protected resource group '${RG}'."
    exit 1
    ;;
esac

if [[ "$(az group exists --name "$RG" --output tsv 2>/dev/null)" != "true" ]]; then
  echo "Resource group ${RG} does not exist; nothing to destroy."
  exit 0
fi

echo ""
echo "⚠️  DESTRUCTIVE: this deletes resource group '${RG}' and ALL resources in it."
echo ""
az resource list --resource-group "$RG" --query "[].{name:name,type:type}" --output table 2>/dev/null || true
echo ""

if [[ "$AUTO_YES" != "true" ]]; then
  read -r -p "Type the resource group name to confirm: " CONFIRM
  [[ "$CONFIRM" == "$RG" ]] || { echo "Aborted."; exit 1; }
fi

echo "Deleting ${RG}..."
az group delete --name "$RG" --yes
echo "✓ Deleted ${RG}"
