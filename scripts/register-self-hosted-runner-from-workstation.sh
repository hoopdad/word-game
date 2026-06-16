#!/usr/bin/env bash
set -euo pipefail

# Register the Azure VM self-hosted runner from the operator workstation.
# Auth is obtained locally (gh login or GH_RUNNER_TOKEN override), then only a
# short-lived registration token is sent to the VM via az vm run-command.

RESOURCE_GROUP="${RESOURCE_GROUP:-MIKEO-LAB-INFRA-RG}"
VM_NAME="${VM_NAME:-vm-runner-mikeo-lab-infra}"
GITHUB_REPO="${GITHUB_REPO:-hoopdad/word-game}"
RUNNER_LABEL="${RUNNER_LABEL:-wordgame-spoke}"
RUNNER_NAME="${RUNNER_NAME:-${VM_NAME}}"
RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_VERSION="${RUNNER_VERSION:-2.327.1}"

echo "Resolving GitHub registration token for ${GITHUB_REPO}..."
if [[ -n "${GH_RUNNER_TOKEN:-}" ]]; then
  REG_TOKEN="$(
    curl -fsSL -X POST \
      -H "Authorization: Bearer ${GH_RUNNER_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
  )"
else
  REG_TOKEN="$(gh api -X POST "repos/${GITHUB_REPO}/actions/runners/registration-token" --jq '.token')"
fi

if [[ -z "${REG_TOKEN}" ]]; then
  echo "Failed to resolve runner registration token."
  exit 1
fi

echo "Registering runner on VM ${VM_NAME} in ${RESOURCE_GROUP}..."
REMOTE_SCRIPT="$(cat <<EOF
set -euo pipefail
RUNNER_USER='${RUNNER_USER}'
RUNNER_HOME="/home/\${RUNNER_USER}"
RUNNER_DIR="\${RUNNER_HOME}/actions-runner"
RUNNER_VERSION='${RUNNER_VERSION}'
RUNNER_NAME='${RUNNER_NAME}'
RUNNER_LABEL='${RUNNER_LABEL}'
GITHUB_REPO='${GITHUB_REPO}'
REG_TOKEN='${REG_TOKEN}'

id "\${RUNNER_USER}" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "\${RUNNER_USER}"
mkdir -p "\${RUNNER_DIR}"
chown -R "\${RUNNER_USER}:\${RUNNER_USER}" "\${RUNNER_DIR}"
cd "\${RUNNER_DIR}"

if [[ ! -x "./config.sh" ]]; then
  ARCH=\$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
  curl --max-time 120 -fsSL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-\${ARCH}-\${RUNNER_VERSION}.tar.gz"
  tar xzf actions-runner.tar.gz
  rm -f actions-runner.tar.gz
  chown -R "\${RUNNER_USER}:\${RUNNER_USER}" "\${RUNNER_DIR}"
fi

if [[ -f ".runner" ]]; then
  ./svc.sh stop || true
  ./svc.sh uninstall || true
  sudo -u "\${RUNNER_USER}" ./config.sh remove --token "\${REG_TOKEN}" || true
fi

sudo -u "\${RUNNER_USER}" ./config.sh --unattended \
  --url "https://github.com/\${GITHUB_REPO}" \
  --token "\${REG_TOKEN}" \
  --name "\${RUNNER_NAME}" \
  --labels "self-hosted,\${RUNNER_LABEL}" \
  --replace

./svc.sh install "\${RUNNER_USER}"
./svc.sh start
EOF
)"

az vm run-command invoke \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${VM_NAME}" \
  --command-id RunShellScript \
  --scripts "${REMOTE_SCRIPT}" >/dev/null

echo "Waiting for online runner with label ${RUNNER_LABEL}..."
for i in {1..30}; do
  RUNNER_NAME_ONLINE="$(gh api "repos/${GITHUB_REPO}/actions/runners" --jq ".runners[] | select(any(.labels[]?; .name == \"${RUNNER_LABEL}\")) | select(.status == \"online\") | .name" | head -n 1 || true)"
  if [[ -n "${RUNNER_NAME_ONLINE}" ]]; then
    echo "Runner is online: ${RUNNER_NAME_ONLINE}"
    exit 0
  fi
  sleep 2
done

echo "Runner registration command completed, but online state was not observed yet."
exit 1
