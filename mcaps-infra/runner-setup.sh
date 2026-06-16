#!/bin/bash
set -e

# GitHub Actions Runner Cloud-Init Setup Script
# This runs automatically when the Azure VM is first created
# The GH_TOKEN must be passed as an environment variable

RUNNER_USER="runner"
RUNNER_HOME="/home/$${RUNNER_USER}"
RUNNER_DIR="$${RUNNER_HOME}/actions-runner"
RUNNER_VERSION="2.327.1"
RUNNER_NAME="vm-runner-$$(hostname)"
RUNNER_LABEL="wordgame-spoke"
GITHUB_REPO="hoopdad/word-game"
# GH_TOKEN must be provided as environment variable
LOG_FILE="/var/log/runner-setup.log"

# Log all output
exec > "$$LOG_FILE" 2>&1

echo "=== GitHub Actions Runner Setup Starting ==="
echo "Timestamp: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -z "$$GH_TOKEN" ]]; then
  echo "ERROR: GH_TOKEN not provided"
  exit 1
fi

# Create runner user
echo "Creating runner user..."
id "$$RUNNER_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$$RUNNER_USER" || true

# Setup directory
echo "Setting up runner directory..."
mkdir -p "$$RUNNER_DIR"
chown -R "$${RUNNER_USER}:$${RUNNER_USER}" "$$RUNNER_DIR"
cd "$$RUNNER_DIR"

# Download runner
echo "Downloading runner v$$RUNNER_VERSION..."
ARCH=$$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
if ! curl --connect-timeout 30 --max-time 300 -fsSL -o actions-runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v$$RUNNER_VERSION/actions-runner-linux-$${ARCH}-$$RUNNER_VERSION.tar.gz"; then
  echo "ERROR: Failed to download runner"
  exit 1
fi

tar xzf actions-runner.tar.gz
rm -f actions-runner.tar.gz
chown -R "$${RUNNER_USER}:$${RUNNER_USER}" "$$RUNNER_DIR"

# Get registration token
echo "Getting registration token from GitHub..."
REG_TOKEN=$$(curl --connect-timeout 30 --max-time 30 -fsSL -X POST \
  -H "Authorization: Bearer $$GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$$GITHUB_REPO/actions/runners/registration-token" \
  | jq -er '.token' || echo "")

if [[ -z "$$REG_TOKEN" ]]; then
  echo "ERROR: Failed to get registration token"
  exit 1
fi

# Configure runner
echo "Configuring runner as '$$RUNNER_NAME'..."
sudo -u "$$RUNNER_USER" ./config.sh --unattended \
  --url "https://github.com/$$GITHUB_REPO" \
  --token "$$REG_TOKEN" \
  --name "$$RUNNER_NAME" \
  --labels "self-hosted,$$RUNNER_LABEL" \
  --replace

# Install and start service
echo "Installing and starting systemd service..."
./svc.sh install "$$RUNNER_USER"
./svc.sh start

# Wait for service to be ready
sleep 3

# Verify
if systemctl is-active --quiet actions-runner; then
  echo "✓ Runner service is active and running"
else
  echo "⚠ Warning: Runner service status unclear, check manually"
fi

echo "=== GitHub Actions Runner Setup Complete ==="
echo "Timestamp: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Log: $$LOG_FILE"
