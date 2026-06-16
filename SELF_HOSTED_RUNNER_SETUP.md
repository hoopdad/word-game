# Self-Hosted Runner Setup

## Overview

The GitHub Actions CD workflow for this project uses a persistent self-hosted runner on an Azure VM (`vm-runner-mikeo-lab-infra`). 

**Key difference from before:** The runner is now set up ONCE at VM creation time, not provisioned dynamically on every workflow run. This eliminates the timing race conditions that caused workflow hangs.

## One-Time Setup

The runner needs to be registered once on the VM. This is a one-time manual step:

### Prerequisites
- VM `vm-runner-mikeo-lab-infra` in resource group `MIKEO-LAB-INFRA-RG`
- GitHub Personal Access Token with `admin:org_hook` and `repo` scopes
- SSH access to the VM

### Steps

1. **SSH to the VM:**
   ```bash
   az vm show --resource-group MIKEO-LAB-INFRA-RG --name vm-runner-mikeo-lab-infra --show-details --query publicIps
   ssh azureuser@<public-ip>
   ```

2. **Create runner setup script:**
   ```bash
   sudo bash << 'SETUP'
   #!/bin/bash
   set -eu
   
   RUNNER_USER="runner"
   RUNNER_HOME="/home/${RUNNER_USER}"
   RUNNER_DIR="${RUNNER_HOME}/actions-runner"
   RUNNER_VERSION="2.327.1"
   RUNNER_NAME="vm-runner-mikeo-lab-infra"
   RUNNER_LABEL="wordgame-spoke"
   GITHUB_REPO="hoopdad/word-game"
   GH_TOKEN="${1}"
   
   if [[ -z "${GH_TOKEN}" ]]; then
     echo "Usage: $0 <github-token>"
     exit 1
   fi
   
   # Create runner user
   useradd --create-home --shell /bin/bash "${RUNNER_USER}" || true
   
   # Setup directory
   mkdir -p "${RUNNER_DIR}"
   chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_DIR}"
   cd "${RUNNER_DIR}"
   
   # Download runner
   ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
   curl -fsSL -o actions-runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
   tar xzf actions-runner.tar.gz
   
   # Get registration token
   REG_TOKEN=$(curl -fsSL -X POST \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     -H "Accept: application/vnd.github+json" \
     "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
     | jq -er '.token')
   
   # Configure
   sudo -u "${RUNNER_USER}" ./config.sh --unattended \
     --url "https://github.com/${GITHUB_REPO}" \
     --token "${REG_TOKEN}" \
     --name "${RUNNER_NAME}" \
     --labels "self-hosted,${RUNNER_LABEL}" \
     --replace
   
   # Install and start service
   ./svc.sh stop || true
   ./svc.sh uninstall || true
   ./svc.sh install "${RUNNER_USER}"
   ./svc.sh start
   
   echo "✓ Runner registered and started"
   systemctl status actions-runner
   SETUP
   ```

   When prompted, provide your GitHub token.

3. **Verify the runner is online:**
   ```bash
   gh api repos/hoopdad/word-game/actions/runners --jq '.runners[] | {name, status, labels}'
   ```

   You should see your runner listed with status `online` and label `wordgame-spoke`.

## Workflow Behavior

- The `deploy-apps` job in the CD workflow now uses the hardcoded runner labels: `["self-hosted", "wordgame-spoke"]`
- When triggered, the job will wait for the runner to be available
- The runner stays running between CD invocations (configurable via `RUNNER_AUTO_DEALLOCATE` repo variable)
- No more dynamic provisioning = no more race conditions or hangs

## Troubleshooting

**Runner not showing in GitHub UI:**
```bash
# SSH to VM and check service status
sudo systemctl status actions-runner
sudo journalctl -u actions-runner -n 100
```

**Stuck workflow job:**
- If a job is stuck waiting for the runner, verify the runner is online
- Check VM is running: `az vm get-instance-view --resource-group MIKEO-LAB-INFRA-RG --name vm-runner-mikeo-lab-infra --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv`
- Start VM if needed: `az vm start --resource-group MIKEO-LAB-INFRA-RG --name vm-runner-mikeo-lab-infra`

## Clean Up

To remove the runner from GitHub (but keep the VM):
```bash
gh api -X DELETE "repos/hoopdad/word-game/actions/runners/{runner-id}"
```

Then on the VM:
```bash
sudo /home/runner/actions-runner/svc.sh uninstall
```
