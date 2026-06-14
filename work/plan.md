# Plan

## Milestone: bootstrap-foundation
- [x] Create minimal monorepo directories (`apps/*`, `infra`, `packages/shared`, `scripts`, `work`).
- [x] Add root npm workspace scaffold with baseline scripts for install/build/test/lint/start.
- [x] Add runnable stubs for `web`, `api`, and `agent` workspaces.
- [x] Add `packages/shared` baseline with `contracts` and `types` starter boundaries.
- [x] Add local operator scripts: `scripts/verify-local.sh` and `scripts/watch-workflow.sh`.
- [x] Record bootstrap timeline artifact at `work/timeline/bootstrap-foundation.jsonl`.
- [x] Run local coherence checks (`npm install`, `build`, `test`, `lint`, `verify-local`, start-script smoke checks).

## Milestone: ci-cd-pipelines
- [x] Add GitHub Actions `CI` workflow with practical path filters and staged component jobs (`web`, `api`, `agent`, `infra`).
- [x] Add GitHub Actions `CD` workflow with infra-first deployment gating and app deploy fan-out.
- [x] Configure OIDC-based Azure login structure and default deployment region `centralus`.
- [x] Add container build definitions for deployable `web`, `api`, and `agent` services.
- [x] Update pipeline usage docs and runbook references.
- [ ] Push branch and record PR URL after local verification.

## Milestone: deploy-validate-release
- [x] Configure GitHub OIDC secrets/variables for Azure deployment.
- [x] Trigger CD with `location=centralus`.
- [x] Capture failure diagnostics from workflow logs.
- [x] Patch infra defaults to keep Central US while disabling optional Foundry/RBAC resources that require extra permissions/sku alignment.
- [ ] Re-run CD and verify successful infra-first deployment for web/api/agent.

## Blockers
- Awaiting rerun of CD after infra/workflow patch.
