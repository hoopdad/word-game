---
name: ci-cd
description: Enforce and operate this repository’s CI/CD model: CI on PR lifecycle, CD on merge-to-main push, persistent Azure self-hosted runner, workstation-driven runner registration, and no manual CI/CD dispatch.
---

# Word Game CI/CD Skill

## Purpose

Use this skill to keep CI/CD reliable and policy-compliant for this repository.

Expected outcomes:

- CI runs automatically on PR lifecycle events into `main`.
- CD runs automatically on `push` to `main` (the merge path).
- No manual `workflow_dispatch` for CI or CD.
- Self-hosted Azure VM runner is persistent and fully tooled.
- Runner registration is done from operator workstation, never from a GitHub Action.

## Invoke When

Use this skill when asked to:

- fix broken CI/CD behavior or hangs
- enforce trigger policy for PR/merge-driven pipelines
- remediate self-hosted runner availability or tooling
- harden runner subnet outbound connectivity
- eliminate circular dependency in runner registration

## Repository Policy (Authoritative)

1. **CI trigger:** PR lifecycle (`opened`, `reopened`, `synchronize`, `ready_for_review`) targeting `main`.
2. **CD trigger:** `push` to `main` (caused by merged PR).
3. **Do not** rely on manual dispatch for CI/CD.
4. **Do not** register/auth the self-hosted runner from a GitHub Action.
5. Register runner from workstation script using local `gh` auth, then configure VM via Azure control plane.

## Required Runner Model

- Label set used by jobs: `self-hosted`, `wordgame-spoke`.
- Runner VM must be long-lived (not ephemeral per run).
- Toolchain on VM must include at minimum:
  - Azure CLI
  - Terraform CLI
  - Node/npm
  - Docker
  - git, curl, jq, unzip, build-essential
- Subnet must allow outbound internet for package/tool installation and dependency restore.

## Files In Scope

- `.github/workflows/ci.yml`
- `.github/workflows/cd.yml`
- `mcaps-infra/runner.tf`
- `mcaps-infra/runner-setup.sh`
- `scripts/register-self-hosted-runner-from-workstation.sh`
- `SELF_HOSTED_RUNNER_SETUP.md`

## Implementation Rules

1. Keep CI on PR events only; keep CD on push-to-main only.
2. Remove or avoid `workflow_dispatch` paths for CI/CD.
3. Keep OIDC-compatible trigger context for Azure login in CD.
4. Keep runner registration out of workflows (`.github/workflows/setup-runner.yml` must not be reintroduced).
5. Prefer local `gh` auth in workstation registration script.
   - Optional local override: `GH_RUNNER_TOKEN` (from operator secret store).
6. Preserve existing path filters and deploy gating logic unless explicitly changed by user request.

## Runner Registration Procedure

Use:

```bash
scripts/register-self-hosted-runner-from-workstation.sh
```

Behavior:

- Gets short-lived registration token from GitHub using local auth.
- Pushes registration/config commands to VM with `az vm run-command invoke`.
- Verifies runner appears online with label `wordgame-spoke`.

## Validation Checklist

After changes:

1. PR CI completes successfully on the feature branch.
2. PR merges to `main`.
3. CD auto-triggers on `push` to `main` and completes successfully.
4. Runner is online in GitHub API:
   - `gh api repos/hoopdad/word-game/actions/runners`

## Final Response Requirements

Always report:

- exactly which files were changed
- CI run ID and conclusion
- post-merge CD run ID and conclusion
- whether runner registration path remains workstation-only
