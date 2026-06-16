#!/bin/bash
set -eu

# GitHub Actions Self-Hosted Runner Setup
# This script registers a self-hosted runner on the VM with the label "wordgame-spoke"
# Usage: ./setup-self-hosted-runner.sh <github-token>

GH_TOKEN="${1:-}"
if [[ -z "$GH_TOKEN" ]]; then
  echo "Usage: $0 <github-token>"
  echo ""
  echo "GitHub token must have repo scope and admin:org_hook permissions."
  exit 1
fi

RUNNER_USER="runner"
RUNNER_HOME="/home/${RUNNER_USER}"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"
RUNNER_VERSION="2.327.1"
RUNNER_NAME="vm-runner-mikeo-lab-infra"
RUNNER_LABEL="wordgame-spoke"
GITHUB_REPO="hoopdad/word-game"

set -x  # Show commands

# Create runner user
id "$RUNNER_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$RUNNER_USER"

# Setup directory
mkdir -p "$RUNNER_DIR"
chown -R "${RUNNER_USER}:${RUNNER_USER}" "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download runner
ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
echo "Downloading actions-runner-linux-${ARCH}-${RUNNER_VERSION}..."
curl --max-time 120 -fsSL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
tar xzf actions-runner.tar.gz
rm -f actions-runner.tar.gz

# Get registration token
echo "Getting registration token..."
REG_TOKEN=$(curl --max-time 30 -fsSL -X POST \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
  | jq -er '.token')

# Configure runner
echo "Configuring runner..."
sudo -u "$RUNNER_USER" ./config.sh --unattended \
  --url "https://github.com/${GITHUB_REPO}" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "self-hosted,${RUNNER_LABEL}" \
  --replace

# Install and start service
echo "Installing systemd service..."
./svc.sh install "$RUNNER_USER"
./svc.sh start

# Verify
echo ""
echo "✓ Runner setup complete!"
systemctl status actions-runner

# Wait for runner to register
echo ""
echo "Waiting for runner to appear in GitHub..."
for i in {1..30}; do
  REGISTERED=$(curl --max-time 10 -fsSL \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners?per_page=100" \
    | jq -r --arg lbl "$RUNNER_LABEL" '.runners[] | select(any(.labels[]?; .name == $lbl)) | select(.status == "online") | .name' \
    | head -n 1)
  
  if [[ -n "$REGISTERED" ]]; then
    echo "✓ Runner registered and online: $REGISTERED"
    exit 0
  fi
  
  echo "  [$i/30] Waiting for runner to register..."
  sleep 2
done

echo "⚠️ Runner not yet visible in GitHub (may take a moment)"
exit 0
