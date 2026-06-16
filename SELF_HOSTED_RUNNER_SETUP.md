# Self-Hosted Runner Setup

## Policy

Runner registration must be executed from an operator workstation, not from a GitHub Action workflow. This avoids circular dependency failures when self-hosted capacity is required to run CD.

## One-time/repair registration flow

### Prerequisites

- Local `gh` is authenticated for `hoopdad/word-game`
- Local `az` is authenticated to the spoke subscription
- VM exists: `vm-runner-mikeo-lab-infra` in `MIKEO-LAB-INFRA-RG`

### Register from workstation

From repository root:

```bash
scripts/register-self-hosted-runner-from-workstation.sh
```

Optional overrides:

```bash
RESOURCE_GROUP=MIKEO-LAB-INFRA-RG \
VM_NAME=vm-runner-mikeo-lab-infra \
GITHUB_REPO=hoopdad/word-game \
RUNNER_LABEL=wordgame-spoke \
scripts/register-self-hosted-runner-from-workstation.sh
```

The script resolves a short-lived runner registration token using local GitHub auth and configures the runner on the VM via `az vm run-command invoke`.

## Verify

```bash
gh api repos/hoopdad/word-game/actions/runners --jq '.runners[] | {name, status, labels}'
```

Expected: runner label `wordgame-spoke` with status `online`.

## Troubleshooting

VM status:

```bash
az vm get-instance-view \
  --resource-group MIKEO-LAB-INFRA-RG \
  --name vm-runner-mikeo-lab-infra \
  --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus" -o tsv
```

Runner service logs (via VM shell):

```bash
sudo systemctl status actions-runner
sudo journalctl -u actions-runner -n 100
```
