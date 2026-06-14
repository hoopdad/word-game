# Execution Order Handoff (Parallel Waves + Gates)

## Dependency Model
- Serialize only where hard dependencies exist.
- Parallelize by service boundary (`web`, `api`, `agent`, `infra`, `ci`), with shared contract checkpoints.

## Wave 0 — Repo/bootstrap gate (blocking)
Prerequisites:
1. Initialize/restore `.git` metadata and remote.
2. Scaffold code layout (`apps/web`, `apps/api`, `services/category-agent`, `packages/contracts`, `infra`, `.github/workflows`, `scripts`).
3. Add runbook-required scripts:
   - `scripts/verify-local.sh`
   - `scripts/watch-workflow.sh`

Deliverable gate: baseline passes local verify stub and includes runnable project manifests.

## Wave 1 — Parallel foundation
Parallel tracks:
- **Track A (Contracts)**: define shared DTO/event schemas + validation package.
- **Track B (Web shell)**: landing/auth shell, route guards, basic dashboard scaffold.
- **Track C (API shell)**: auth middleware, health/version endpoints, profile/name endpoints.
- **Track D (Agent shell)**: job interface + Foundry client adapter abstraction.
- **Track E (Infra shell)**: ACA/Cosmos/KeyVault/ACR/VNet modules and environments.
- **Track F (CI)**: lint/test/security and infra-first deployment workflows.

Gate to exit Wave 1:
- Shared contracts published/consumed by web+api+agent.

## Wave 2 — Core gameplay primitives
Parallel tracks after Wave 1 gate:
- **Track C1 (API game lock/state)**: global lock, presence, active game state machine.
- **Track D1 (Agent generation)**: source fetch fan-out, extraction/filter pipeline, job completion callbacks.
- **Track B1 (Web lobby/wait)**: name selection flow, wait-state polling, dashboard cards.
- **Track E1 (Infra hardening)**: private endpoints, managed identity role assignments, ingress/WAF policy.

Gate to exit Wave 2:
- Start-game path works end-to-end through category generation completion.

## Wave 3 — Round engine + scoring
Parallel tracks:
- **Track C2 (API rounds)**: role assignment, countdown, 2-minute timer, guess-correct loop, rotation.
- **Track B2 (Web round UX)**: role views, timer, score updates, end-round transitions.
- **Track C3 (Projections)**: total game count + top10 all-time + top3 today updater/query APIs.

Gate to exit Wave 3:
- Full game from start to winner screens with persisted scoring.

## Wave 4 — Production gates
Parallel tracks:
- E2E/integration tests (auth -> profile -> game -> scoring -> reset)
- Security and quality scans from NFR (`semgrep`, `bandit`, `checkov`, eslint security, trivy)
- CI/CD run validation and deployment verification in Azure

Exit criteria:
- Infra deployed first, then services deployed.
- Required CI/CD checks successful (or intentionally gated/skipped with evidence).
- Operator artifacts updated under `work/`.

## File-Conflict Minimization Strategy
- Contracts-only PRs before heavy feature PRs.
- One worker per top-level service directory.
- Cross-service changes only through `packages/contracts` and agreed API versions.
- Infra and workflow changes isolated from feature logic.

## Feasibility Blockers + Exact Unblock Actions
1. **Missing git repository metadata** (`.git` absent)
   - Action: initialize repo or restore clone with remote, then create `feature/*` branch.
2. **No implementation scaffold/package manifests**
   - Action: bootstrap monorepo structure and root workspace config.
3. **Runbook-required scripts absent**
   - Action: add `scripts/verify-local.sh` and `scripts/watch-workflow.sh` before worker execution.
4. **CI/CD workflows absent**
   - Action: add infra-first GitHub Actions and environment/OIDC configuration.
5. **Azure deployment prerequisites not declared in repo**
   - Action: document required subscription, Entra tenant/app registrations, OIDC federated credentials, and required secrets/variables in runbook appendix.
