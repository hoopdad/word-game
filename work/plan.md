# Plan

## Milestone: bootstrap-foundation
- [x] Create minimal monorepo directories (`apps/*`, `infra`, `packages/shared`, `scripts`, `work`).
- [x] Add root npm workspace scaffold with baseline scripts for install/build/test/lint/start.
- [x] Add runnable stubs for `web`, `api`, and `agent` workspaces.
- [x] Add `packages/shared` baseline with `contracts` and `types` starter boundaries.
- [x] Add local operator scripts: `scripts/verify-local.sh` and `scripts/watch-workflow.sh`.
- [x] Record bootstrap timeline artifact at `work/timeline/bootstrap-foundation.jsonl`.
- [x] Run local coherence checks (`npm install`, `build`, `test`, `lint`, `verify-local`, start-script smoke checks).

## Blockers
- Git repository metadata (`.git`) is missing in this working directory, so branch/PR/CI workflow steps are blocked until repository initialization or checkout is restored.
