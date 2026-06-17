#!/usr/bin/env bash
set -euo pipefail

# Provision the persistent runner VM with Azure CLI.
# The workload subnet, NIC, NAT, and related runner networking remain managed by Terraform.

RESOURCE_GROUP="${RESOURCE_GROUP:-MIKEO-LAB-INFRA-RG}"
VM_NAME="${VM_NAME:-vm-runner-mikeo-lab-infra}"
NIC_NAME="${NIC_NAME:-nic-runner-mikeo-lab-infra}"
IDENTITY_NAME="${IDENTITY_NAME:-id-mikeo-lab-infra}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v4}"
RUNNER_USER="${RUNNER_USER:-runneradmin}"
RUNNER_SETUP_FILE="${RUNNER_SETUP_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mcaps-infra/runner-setup.sh}"

if az vm show --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" >/dev/null 2>&1; then
  echo "VM ${VM_NAME} already exists; starting it if needed."
  az vm start --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" >/dev/null
  exit 0
fi

if ! az network nic show --resource-group "${RESOURCE_GROUP}" --name "${NIC_NAME}" >/dev/null 2>&1; then
  echo "NIC ${NIC_NAME} was not found in ${RESOURCE_GROUP}."
  exit 1
fi

if [[ ! -f "${RUNNER_SETUP_FILE}" ]]; then
  echo "Runner bootstrap script not found: ${RUNNER_SETUP_FILE}"
  exit 1
fi

UAMI_ID="$(az identity show --resource-group "${RESOURCE_GROUP}" --name "${IDENTITY_NAME}" --query id -o tsv 2>/dev/null || true)"

echo "Creating VM ${VM_NAME} in ${RESOURCE_GROUP}..."
az vm create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --nics "${NIC_NAME}" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
  --size "${VM_SIZE}" \
  --admin-username "${RUNNER_USER}" \
  --generate-ssh-keys \
  --custom-data "${RUNNER_SETUP_FILE}" \
  --tags managed_by=az-cli workload=word-game environment=lab \
  >/dev/null

if [[ -n "${UAMI_ID}" ]]; then
  echo "Attaching managed identity ${IDENTITY_NAME}..."
  az vm identity assign --resource-group "${RESOURCE_GROUP}" --name "${VM_NAME}" --identities "${UAMI_ID}" >/dev/null
fi

echo "VM provisioning complete."
