#!/bin/bash
set -e

# GitHub Actions Runner Cloud-Init Setup Script
# This runs automatically when the Azure VM is first created
# This script intentionally does not register the runner with GitHub.
# Registration is performed from an operator workstation script to avoid
# circular CI dependencies.

RUNNER_USER="runner"
RUNNER_HOME="/home/$${RUNNER_USER}"
RUNNER_DIR="$${RUNNER_HOME}/actions-runner"
RUNNER_VERSION="2.327.1"
RUNNER_NAME="vm-runner-$$(hostname)"
RUNNER_LABEL="$${RUNNER_LABEL_VALUE:-wordgame-spoke}"
GITHUB_REPO="hoopdad/word-game"
LOG_FILE="/var/log/runner-setup.log"

# Log all output
exec > "$$LOG_FILE" 2>&1

echo "=== GitHub Actions Runner Setup Starting ==="
echo "Timestamp: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Create runner user first so group and profile setup is reliable
echo "Creating runner user..."
id "$$RUNNER_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$$RUNNER_USER" || true

# Install deployment/build tools first
echo "=== Installing deployment tools ==="
echo "Updating package manager..."
apt-get update --quiet || true

echo "Installing base packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y --quiet \
  ca-certificates curl git jq unzip gnupg lsb-release build-essential || true

echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash > /dev/null 2>&1 || echo "Azure CLI installation had issues, continuing..."

echo "Installing Terraform..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg 2>/dev/null || true
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $$(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
apt-get update --quiet || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --quiet terraform || true

echo "Installing Docker (apt)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y --quiet docker.io || true

echo "Installing Node.js 20 + npm (NodeSource)..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --quiet nodejs || true

echo "Creating docker group and adding runner user..."
groupadd docker 2>/dev/null || true
usermod -aG docker "$$RUNNER_USER" 2>/dev/null || true

echo "Setting PATH environment for runner user..."
mkdir -p "$$RUNNER_HOME/.bashrc.d"
echo 'export PATH=/usr/local/bin:/usr/bin:/bin:$PATH' >> "$$RUNNER_HOME/.bashrc.d/path"

# Setup directory
echo "Setting up runner directory..."
mkdir -p "$$RUNNER_DIR"
chown -R "$${RUNNER_USER}:$${RUNNER_USER}" "$$RUNNER_DIR"
echo 'PATH=/usr/local/bin:/usr/bin:/bin' > "$$RUNNER_DIR/.env"
chown "$${RUNNER_USER}:$${RUNNER_USER}" "$$RUNNER_DIR/.env"
cd "$$RUNNER_DIR"

echo "=== Runner host bootstrap complete (registration deferred) ==="
echo "Timestamp: $$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Runner label target: $$RUNNER_LABEL"
echo "Use scripts/register-self-hosted-runner-from-workstation.sh from operator workstation to register this VM."
echo "Log: $$LOG_FILE"
