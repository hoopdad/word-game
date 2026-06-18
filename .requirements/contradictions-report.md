# Contradictions Report

Audit date: 2026-06-17

## Executive summary

Confirmed contradictions were found across child-repo agent instructions and CI/CD workflows. The biggest issues are:

1. some workflows still use GitHub-hosted runners even though guardrails require self-hosted only;
2. CI workflows do not consistently implement the required `lint → security scan → test → build` order;
3. CD workflows use inconsistent secret names and do not consistently satisfy the `:sha` + `:latest` tagging/deploy rules;
4. some child agent instructions explicitly normalize skipping build/lint/test steps that platform guardrails require;
5. `word-game-infra` is missing specialist/critic agent files, and no child repo currently has `copilot-instructions.md`.

---

## 1) CI/CD runner contradictions

### Contradiction
Guardrails require **self-hosted runners only** for CI/CD.

### Evidence
- `.copilot/guardrails/nfr.yml:82-85` requires all CI on self-hosted runners and ephemeral isolation.
- `.requirements/platform-guardrails.yml:55-57` requires “GitHub Actions on self-hosted runners only”.
- `../word-game-agent/.github/workflows/ci.yml:10-20` uses `runs-on: ubuntu-latest` for the `lint` job.
- `../word-game-agent/.github/workflows/cd.yml:9-16` uses `runs-on: ubuntu-latest` for deployment.
- `../word-game-waf/.github/workflows/cd.yml:16-22` uses `runs-on: ubuntu-latest` for deployment.

### Impact
These workflows violate the platform runner policy and weaken the isolation model required by the NFRs.

---

## 2) CI stage/order contradictions

### Contradiction
Guardrails require CI to run **lint, security scan, unit tests, then build**, with fast checks before slower ones.

### Evidence
- `.copilot/guardrails/nfr.yml:86-89` requires `lint, security scan, unit tests` and fail-fast ordering.
- `.requirements/platform-guardrails.yml:58-61` requires `CI: lint → security scan → test → build (fail fast)`.

#### Web repo
- `../word-game-web/.github/workflows/ci.yml:9-56` has `lint`, `test`, and `build`, but **no security scan job**.
- `../word-game-web/.github/workflows/ci.yml:9-56` defines the jobs independently with **no `needs:` chain**, so test/build are not gated on lint.

#### API repo
- `../word-game-api/.github/workflows/ci.yml:8-20` runs lint/format/test in one job, but has **no security scan stage** and **no build stage**.

#### Agent repo
- `../word-game-agent/.github/workflows/ci.yml:9-35` has separate `lint` and `test` jobs, but **no security scan job** and **no build job**.
- `../word-game-agent/.github/workflows/ci.yml:9-35` also has **no `needs:` dependency**, so tests are not fail-fast gated on lint.

#### WAF repo
- `../word-game-waf/.github/workflows/ci.yml:12-51` has only a `validate` job; it does **not implement the required lint → security scan → test → build structure**.

### Impact
The platform-required quality gate is not implemented consistently, so repos can pass CI without the mandated security stage or ordered checks.

---

## 3) CD image-tagging/deployment contradictions

### Contradiction
Guardrails require CD to push **both `:sha` and `:latest`** tags, then force deployment of the latest image.

### Evidence
- `.copilot/guardrails/nfr.yml:91-95` requires CD after successful CI on `main`, OIDC auth, `:sha` + `:latest` tags, and deploy behavior tied to latest image.
- `.requirements/platform-guardrails.yml:59-60` requires `Container images tagged with :sha and :latest`.

#### WAF repo
- `../word-game-waf/.github/workflows/cd.yml:35-45` builds/pushes only a SHA-tagged image; **no `:latest` tag is built or pushed**.

#### All service repos
- `../word-game-web/.github/workflows/cd.yml:50-55`
- `../word-game-api/.github/workflows/cd.yml:33-44`
- `../word-game-agent/.github/workflows/cd.yml:40-45`
- `../word-game-waf/.github/workflows/cd.yml:47-55`

All four deployments update Container Apps to a **SHA-pinned image**, not a `:latest` image, which does not match the NFR wording.

### Impact
The WAF repo is clearly non-compliant on tagging, and all repos interpret deployment semantics differently from the written guardrail.

---

## 4) Secret-name inconsistencies across repos

### Contradiction
The service repos do not use a consistent secret contract for ACR and resource-group values.

### Evidence

| Repo | ACR secret pattern | Resource group secret pattern | Other notes |
|---|---|---|---|
| web | `ACR_NAME` (`../word-game-web/.github/workflows/cd.yml:42-48`) | `RESOURCE_GROUP` (`../word-game-web/.github/workflows/cd.yml:52-55`) | container app name hard-coded |
| api | `ACR_LOGIN_SERVER` + `ACR_IMAGE_NAME` (`../word-game-api/.github/workflows/cd.yml:23-32`) | `AZURE_RESOURCE_GROUP` (`../word-game-api/.github/workflows/cd.yml:33-44`) | app name secretized |
| agent | `ACR_NAME` (`../word-game-agent/.github/workflows/cd.yml:29-38`) | `AZURE_RESOURCE_GROUP` (`../word-game-agent/.github/workflows/cd.yml:40-45`) | app name hard-coded |
| waf | `ACR_NAME` + `ACR_REPOSITORY` (`../word-game-waf/.github/workflows/cd.yml:35-45`) | `CONTAINER_APP_RESOURCE_GROUP` (`../word-game-waf/.github/workflows/cd.yml:47-55`) | app name secretized |

### Impact
This is an operational contradiction across repos: the same platform pattern has no single secret schema, which increases setup drift and reuse errors.

---

## 5) Agent-instruction contradictions vs platform guardrails

### 5.1 WAF specialist explicitly skips lint/test/build

#### Contradiction
The WAF specialist instructions normalize having no linter, no tests, and no build validation.

#### Evidence
- `../word-game-waf/.github/agents/word-game-waf-specialist.agent.md:12-23` sets validation to:
  - `echo 'no linter'`
  - `echo 'no tests'`
  - `echo 'no build'`
- This conflicts with:
  - `.copilot/guardrails/nfr.yml:82-89` (CI quality gates),
  - `.copilot/guardrails/nfr.yml:102-106` (all services deploy as containers),
  - `.requirements/platform-guardrails.yml:55-62` (required CI/CD pattern).

### 5.2 API and agent specialists declare “no build step”

#### Contradiction
Both Python service specialists say local validation has **no build step**, even though the platform requires containerized services and multi-stage Docker images.

#### Evidence
- `../word-game-api/.github/agents/word-game-api-specialist.agent.md:20-23` says `Build: echo 'no build step (interpreted)'`.
- `../word-game-agent/.github/agents/word-game-agent-specialist.agent.md:20-23` says `Build: echo 'no build step (interpreted)'`.
- This conflicts with:
  - `.copilot/guardrails/nfr.yml:102-106` (“All services deploy as Docker containers”; multi-stage Dockerfiles),
  - `.requirements/platform-guardrails.yml:40-47` (backend/agent must use multi-stage Dockerfile, non-root),
  - `.requirements/platform-guardrails.yml:58-61` (CI requires a build stage).

### Impact
These agent instructions under-enforce the platform contract and can allow specialist handoff without validating the deployable artifact the platform actually uses.

---

## 6) Missing required governance files

### 6.1 `word-game-infra` is missing specialist/critic agent files

#### Evidence
- `.copilot/guardrails/pattern.yml:33-36` defines `infra` as a child repo in the pattern.
- Audit search of `../word-game-infra/.github/agents/*` returned **no files**.

#### Impact
The infra repo is part of the platform pattern but has no specialist/critic agent definitions, unlike the other child repos.

### 6.2 All child repos are missing `copilot-instructions.md`

#### Evidence
- Audit search for `**/copilot-instructions.md` under:
  - `../word-game-web`
  - `../word-game-api`
  - `../word-game-agent`
  - `../word-game-waf`
  - `../word-game-infra`
  returned **no matches**.

#### Impact
There is no shared per-repo Copilot instruction file in any child repo, which increases the chance that repo-specific standards live only in scattered agent files/workflows.

---

## 7) MCP config alignment check

### Result
No hard contradiction was found between child `mcp.json` server names and the MCP servers currently available in the harness environment.

### Evidence
- Web config uses: `lint-local`, `security-scanner`, `usage-tracker` (`../word-game-web/.github/mcp.json:3-22`).
- API config uses: `scaffold-generator`, `lint-local`, `contract-compliance`, `security-scanner`, `usage-tracker` (`../word-game-api/.github/mcp.json:3-35`).
- Agent config uses: `lint-local`, `security-scanner`, `usage-tracker` (`../word-game-agent/.github/mcp.json:3-22`).
- WAF config uses: `lint-local`, `security-scanner`, `usage-tracker` (`../word-game-waf/.github/mcp.json:3-22`).
- Infra config uses: `terraform-local`, `azure-resource-status`, `azure-inspector`, `lint-local`, `security-scanner`, `usage-tracker` (`../word-game-infra/.github/mcp.json:3-41`).

### Note
Agent prose uses shorthand function names such as `run_local_lint`, `security_scan`, `log_usage`, and `get_usage_quality_report`; those map to available MCP functions, so this is a naming-style inconsistency, not a confirmed config mismatch.

---

## Recommended fixes

1. Standardize all CI/CD workflows on self-hosted runners only.
2. Enforce one CI template across repos: `lint → security scan → test → build`, with explicit `needs:` ordering.
3. Standardize deployment secret names across repos (ACR, resource group, container app name).
4. Update CD workflows so every service pushes both `:sha` and `:latest`; clarify whether deployment must use `:latest` or a SHA-pinned image and then make all repos consistent.
5. Rewrite WAF/API/agent specialist instructions so local validation includes the deployable container build where required.
6. Add missing `word-game-infra` specialist/critic agent files.
7. Add `copilot-instructions.md` to each child repo, or explicitly document that agent files are the sole instruction source.
