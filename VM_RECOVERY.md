# VM Recovery and Runner Setup

## Current Status

The CD workflow has been fixed and is now **working correctly**:
- ✅ `detect-changes` job: completes successfully
- ✅ `Deploy infrastructure` job: completes successfully
- ✅ `Deploy apps` job: **queued**, waiting for self-hosted runner

The workflow is no longer hanging. It's now cleanly waiting for the runner to be registered.

## What Happened

The Azure VM (`vm-runner-mikeo-lab-infra`) became stuck during earlier troubleshooting attempts. The run-command extension has a pending operation that won't complete or be canceled via Azure CLI.

## Recovery Steps

### Option 1: Wait for VM to Recover (Fastest)

The VM may recover on its own within a few hours. To check:

```bash
# Check if run-command is now available
az vm run-command invoke \
  --resource-group MIKEO-LAB-INFRA-RG \
  --name vm-runner-mikeo-lab-infra \
  --command-id RunShellScript \
  --scripts 'echo ready' 2>&1 | grep ready
```

If successful, run the setup:

```bash
./scripts/setup-self-hosted-runner.sh "$(gh auth token)"
```

Or via Azure CLI:

```bash
az vm run-command invoke \
  --resource-group MIKEO-LAB-INFRA-RG \
  --name vm-runner-mikeo-lab-infra \
  --command-id RunShellScript \
  --scripts "$(cat scripts/setup-self-hosted-runner.sh)" \
  --parameters "GH_TOKEN=$(gh auth token)"
```

### Option 2: Force Deallocate and Restart

```bash
# Force deallocate
az vm deallocate --resource-group MIKEO-LAB-INFRA-RG --name vm-runner-mikeo-lab-infra --force

# Wait for deallocate to complete (check status)
az vm get-instance-view \
  --resource-group MIKEO-LAB-INFRA-RG \
  --name vm-runner-mikeo-lab-infra \
  --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv

# Start VM
az vm start --resource-group MIKEO-LAB-INFRA-RG --name vm-runner-mikeo-lab-infra

# Wait for startup (5-10 minutes)
# Then run setup
az vm run-command invoke \
  --resource-group MIKEO-LAB-INFRA-RG \
  --name vm-runner-mikeo-lab-infra \
  --command-id RunShellScript \
  --scripts "$(cat scripts/setup-self-hosted-runner.sh)" \
  --parameters "GH_TOKEN=$(gh auth token)"
```

### Option 3: Recreate VM (Nuclear Option)

If the VM is unrecoverable, destroy and recreate it via Terraform:

```bash
cd mcaps-infra

# Destroy the runner VM
terraform destroy --target='azurerm_windows_virtual_machine.runner[0]'

# Reapply
terraform apply

# Then run setup on new VM (see steps above)
```

## Verification

Once the runner is registered, verify it appears in GitHub:

```bash
gh api repos/hoopdad/word-game/actions/runners --jq '.runners[] | {name, status, labels}'
```

You should see:
```json
{
  "name": "vm-runner-mikeo-lab-infra",
  "status": "online",
  "labels": [
    {"name": "self-hosted"},
    {"name": "wordgame-spoke"}
  ]
}
```

Once the runner is online, the queued CD job will automatically start running.

## Notes

- The workflow fix is **complete and verified** - no more hanging
- The runner setup is a **one-time operation** per VM
- The runner will **stay running** between CD jobs (as per user request)
- The setup script is idempotent - safe to run multiple times
