# Proposed Baseline Revision — enterprise-copilot-fleet-controller

**Baseline analyzed:** `../enterprise-copilot-fleet-controller` (VERSION `0.1.0`, pattern `azure-fullstack`)
**Reference implementation (drifted):** `word-game-harness` (parent/orchestrator) + `word-game-{waf,web,api,agent,infra}` (children)
**Date:** 2026-06-19

This document captures (1) how the baseline currently installs agents / skills / MCP servers /
instructions into new repos, (2) every change that was made to the live `word-game-*` fleet
relative to the baseline, (3) which changes apply to **all repos / the parent / children / specific
stack roles**, and (4) a concrete, ordered list of changes to fold back into a new baseline revision.

---

## 1. How the baseline installs things today

`scripts/init.sh` → `scripts/init-core.sh` (2358 lines) drives install. It renders templates from
`templates/init/` using a chosen `patterns/<pattern>/pattern.yml` + `nfr.yml`. For the
`azure-fullstack` pattern it auto-generates children `-waf, -web, -api, -agent, -infra`.

**What gets written where:**

| Artifact | Location | Scope | Source template |
|----------|----------|-------|-----------------|
| Orchestrator instructions | `.github/copilot-instructions.md` | **parent only** | `templates/init/instructions.md.tmpl` |
| Specialist agent | `<child>/.github/agents/<name>-specialist.agent.md` | each child | `agents/specialist.agent.md.tmpl` |
| Critic agent | `<child>/.github/agents/<name>-critic.agent.md` | each child | `agents/critic.agent.md.tmpl` |
| Deployment agent (template exists, optional) | `<child>/.github/agents/<name>-deployment.agent.md` | each child | `agents/deployment.agent.md.tmpl` |
| MCP config | `.github/mcp.json` | parent (+ children reference) | `mcp.json.tmpl` |
| Guardrail snapshots | `.copilot/guardrails/{pattern,nfr,init-pattern}.yml` + `requirements-docs/` | parent | copied from pattern |
| Platform guardrails | `.requirements/platform-guardrails.yml` | parent/children | `requirements/*.tmpl` |
| Optional workflow templates | `.copilot/workflow-templates/*.yml` | feature-gated | `workflows/*.tmpl` |
| Optional docs | `.copilot/docs/{developer-onboarding,portability-blueprint}.md` | feature-gated | `docs/*.tmpl` |

**Key gaps in the baseline (confirmed by inspection):**

- **No skills mechanism at all.** There is no `skills/` template, no install step, and no
  `grep`-able skill handling in `init-core.sh` (the only "skill" hits are the *"MCP Skill/Workflow
  Callouts"* prose section). Every skill in the live fleet is a 100% post-init addition.
- **No `.copilot/topology.md`** generation — the single most-referenced file in live sessions.
- **No orchestrator-level (non specialist/critic) agents** — e.g. the live `e2e-tester` agent.
- **No child `.github/copilot-instructions.md`** generation — children authored their own ad hoc,
  and they have drifted (see §4 contradictions).
- **`mcp.json.tmpl` omits three tools that already ship in `tools/`**: `container-app-diagnostics`,
  `deploy-local`, `quick-deploy`. The live `word-game-harness/.github/mcp.json` wires all three in.
- **`nfr.yml` + instructions hard-code a GitHub Actions / self-hosted-runner / OIDC CI-CD model**,
  but the live fleet migrated entirely to **local `azd up`** deployment.

---

## 2. Inventory of changes observed in the live fleet vs. baseline

### 2a. Parent (`word-game-harness`) additions
- `.copilot/topology.md` (171 lines) — file-location maps for every repo, Azure resource IDs, Entra
  config, request-flow diagram, **deployment-wait polling pattern (replaces `sleep`)**, common-mistakes
  checklist, child-agent dispatch model (`phase="full"`).
- `.github/agents/word-game-e2e-tester.agent.md` — orchestrator-level validation agent (not a
  specialist/critic), with a structured PASS/FAIL report format.
- `.github/skills/`: `container-app-troubleshoot`, `cosmos-db-troubleshoot`, `e2e-test`,
  `entra-vite-spa-auth`, `route-flow-debug`, `spoke-skill` (+ templates).
- `.github/copilot-instructions.md` drift vs `instructions.md.tmpl`:
  - New **"Session Init Checklist"** (call `tool_search_tool_regex` first to discover MCP prefixes).
  - New **"Local Deployment"** section (`azd up` / `azd provision` / `scripts/azd-deploy.sh` / `deploy-local`).
  - New **"MCP Tools" reference table** mapping every tool to a "when to use".
  - Deployment step 10 changed from **"Trigger deployment agent" (GitHub Actions)** → **"Trigger local deployment" (azd)**.
  - Dropped the **Deployment Agent** column from the child-workflow table.
- `.github/mcp.json` adds `container-app-diagnostics`, `deploy-local`, `quick-deploy`.

### 2b. Child specialist/critic agent drift (all children)
Pattern of edits (also see `word-game/mike-changes.txt`):
- **"Known File Locations" table** ("DO NOT search — use directly") — eliminates `find`/`ls`.
- **"Token Efficiency Rules"** block (never `find`/`ls`; batch edits; validate once; one build cycle per fix).
- **Contract-alignment rules** (read `.contracts/*.yml` first; snake_case field names).
- **Removed CI/CD workflow checklists** from agents (obsolete after azd migration).
- Critics streamlined to **hard-gate, instant-FAIL checklist** format.
- Validation commands made **compound** (e.g. `npm run lint && npm test && npm run build && docker build …`).

### 2c. Role-specific (stack) additions
- **web (frontend):** MSAL "Hard Gates" (runtime `redirectUri`, `acquireTokenPopup`, scope build,
  Dockerfile `ARG` ordering, relative `/api` base) + 3-second pre-build validation script; the
  `entra-vite-spa-auth` skill.
- **api (backend):** Entra token-validation quick reference (v1/v2 audience, JWKS URL), `slowapi`
  rate-limit + strict JWT constraints.
- **waf:** Request-flow map, OWASP CRS quick reference (911100 exclusion for `/api/`), nginx rules
  (`map_hash_bucket_size 128`, WebSocket upgrade, CSP for `login.microsoftonline.com`), deploy-last /
  `min_replicas=1`; the `route-flow-debug` skill.
- **agent:** Foundry client configuration reference (`agent_framework.foundry.FoundryChatClient`).
- **infra:** `secure-azure-terraform-coder`, `hub-skill`, `spoke-skill`; ACA networking quick
  reference (ACR public access, VNet AVM exception), documented AVM exceptions, **local azd**
  deployment model, Central US region pin.

---

## 3. Applicability matrix

| Change | All repos | Parent | Children (generic) | Stack role |
|--------|:---------:|:------:|:------------------:|------------|
| Add a **skills install mechanism** to init | ✅ | ✅ | ✅ | — |
| `container-app-troubleshoot` skill | ✅ (any ACA service) | ✅ | ✅ | — |
| `mcp.json`: add `container-app-diagnostics`, `deploy-local`, `quick-deploy` | ✅ | ✅ | — | — |
| "Token Efficiency Rules" block in specialist/critic templates | ✅ | — | ✅ | — |
| "Known File Locations" table convention | — | — | ✅ | per-role seed |
| Compound validation command | — | — | ✅ | per-role |
| `.copilot/topology.md` generation | — | ✅ | — | — |
| Orchestrator-level `e2e-tester` agent | — | ✅ | — | — |
| Orchestrator "Session Init Checklist" + "MCP Tools" table | — | ✅ | — | — |
| **Deployment-model switch** (local-azd vs github-actions) | ✅ | ✅ | ✅ | — |
| Generate/lint child `copilot-instructions.md` | — | — | ✅ | — |
| `entra-vite-spa-auth` skill + MSAL hard gates | — | parent (skill) | — | **frontend** |
| `route-flow-debug` skill + nginx/CRS reference | — | parent (skill) | — | **waf** |
| `cosmos-db-troubleshoot` + `e2e-test` skills | — | ✅ | — | **api/data** |
| Entra token-validation quick reference | — | — | — | **backend** |
| Foundry client reference | — | — | — | **agent** |
| `secure-azure-terraform-coder` / `hub-skill` / `spoke-skill` + AVM exceptions | — | spoke (parent) | — | **infra** |
| Region pin variable (Central US default) | ✅ | ✅ | ✅ | — |

---

## 4. Cross-cutting contradictions the revision must resolve

1. **CI/CD model mismatch.** `patterns/azure-fullstack/nfr.yml` `devops:` (self-hosted runners, OIDC,
   `:sha`/`:latest` push, "min 1 instance via CD") and the orchestrator "Trigger deployment agent"
   step describe **GitHub Actions**. The live fleet deploys via **local `azd up`**. Child
   `copilot-instructions.md` for web/api/waf/agent still document **self-hosted runners, OIDC secrets,
   SHA-named deploys** — all stale. This is the single biggest source of agent confusion and wasted tokens.
2. **Tools shipped but not wired.** `container-app-diagnostics`, `deploy-local`, `quick-deploy` exist
   in `tools/` (and have recent commits) but never reach a generated `mcp.json`.
3. **Region not pinned.** Pattern/NFR never set a region; the fleet standardized on **Central US**.
4. **No durable file map.** Absent `topology.md`, every session re-discovers paths/IDs with `find`/`grep`.

---

## 5. Proposed baseline changes (ordered, actionable)

> Per `MAINTAINING.md`: any change to generated output requires **≥ MINOR** bump and an idempotent
> `migrations/v{OLD}_to_v{NEW}.sh`. Target version: **0.2.0**.

### P0 — Wire existing tools into `mcp.json` *(All repos; trivial, no behavior risk)*
1. Add to `templates/init/mcp.json.tmpl`:
   - `container-app-diagnostics` → `tools/container-app-diagnostics/server.py`
   - `deploy-local` → `tools/deploy-local/server.py`
   - `quick-deploy` → `tools/quick-deploy/server.py`
2. Add their tool names to the orchestrator "MCP Tools" table (see P3).
3. Migration: JSON-merge the three servers into existing `.github/mcp.json` if absent.

### P1 — Add a first-class **skills** install mechanism *(All repos; foundational)*
1. New tree `templates/init/skills/<skill-name>/SKILL.md(.tmpl)` (+ optional `templates/`).
2. In `pattern.yml`, add a `skills:` list with per-skill `scope` (`parent` | `child` | role name)
   and `appliesTo` glob. Example seed for `azure-fullstack`:
   ```yaml
   skills:
     - name: container-app-troubleshoot   # scope: all (parent + every child)
       scope: [parent, child]
     - name: cosmos-db-troubleshoot        # scope: parent
       scope: [parent]
     - name: e2e-test
       scope: [parent]
     - name: entra-vite-spa-auth
       scope: [role:frontend, parent]
     - name: route-flow-debug
       scope: [role:waf, parent]
     - name: secure-azure-terraform-coder  # appliesTo: **/*.tf
       scope: [role:infra]
     - name: hub-skill
       scope: [role:infra]
     - name: spoke-skill
       scope: [role:infra, parent]
   ```
3. `init-core.sh`: new `install_skills()` that renders skills to `<repo>/.github/skills/<name>/` based
   on scope/role. Parameterize project-specific values (resource IDs, FQDNs, client IDs) as template
   vars so skills are portable, not word-game-hardcoded.
4. Seed `templates/init/skills/` with **sanitized** copies of the six live harness skills + three infra
   skills (replace word-game IDs/FQDNs with `__VAR__` placeholders fed from init config / topology).
5. Migration: create `.github/skills/` and drop in scoped skills; never overwrite an existing
   user-edited `SKILL.md`.

### P2 — Add a **deployment-model** switch *(All repos; resolves §4.1)*
1. Add `deployment_model: local-azd | github-actions` to `pattern.yml` (default **`local-azd`** for
   `azure-fullstack`, matching reality).
2. Make `nfr.yml` `devops:` content **conditional** on the model. For `local-azd`, replace the
   self-hosted-runner / OIDC / CD-trigger requirements with azd equivalents (`azd up`, local TF state,
   `az acr build`, `scripts/azd-deploy.sh`).
3. In `instructions.md.tmpl`, gate the deployment step:
   - `local-azd` → emit the **"Local Deployment"** section + step "Trigger local deployment" (azd
     commands + `deploy-local` MCP tool), and **drop** the Deployment Agent column.
   - `github-actions` → keep current behavior + deployment agent.
4. **Stop baking GitHub Actions into child instructions** when model = `local-azd` (see P5).
5. Migration: detect `azure.yaml`/`scripts/azd-deploy.sh`; if present, rewrite the deployment section.

### P3 — Enrich `instructions.md.tmpl` (orchestrator) *(Parent)*
1. Add a **"Session Init Checklist"** block: first action = call `tool_search_tool_regex` with
   `child-agent|repo-index|contract`; never assume MCP unavailable without a direct call.
2. Add an **"MCP Tools" reference table** (tool → when-to-use) — generated from the active `mcp.json`
   server set so it stays in sync, including the P0 additions and skill cross-links.
3. Add a **topology pointer**: "Consult `.copilot/topology.md` FIRST for file locations, IDs, flow."

### P4 — Generate `.copilot/topology.md` *(Parent; highest token-savings ROI)*
1. New `templates/init/topology.md.tmpl` rendered into the parent at init.
2. Auto-populate from known config: child list + per-role **Key File Locations** tables (seeded from
   `default_stack_for_role`), request-flow diagram, deployment model, and a
   **"Deployment Wait Pattern (NO sleep!)"** polling snippet + **"Common Mistakes"** checklist.
3. Leave clearly-marked `TODO` placeholders for runtime-discovered values (resource IDs, FQDNs, Entra
   client IDs) so the orchestrator fills them after first provision — do not hardcode.
4. Cross-reference: specialist/critic "Token Efficiency Rules" point agents at `.copilot/topology.md`
   for IDs/FQDNs instead of searching.

### P5 — Generate & de-stale child `.github/copilot-instructions.md` *(Children; resolves §4.1)*
1. Add `templates/init/child-instructions.md.tmpl` rendered per child (purpose, stack, validation
   commands, agent references, MCP tools, guardrail pointer).
2. Drive CI/CD content from `deployment_model` (P2) so `local-azd` children **omit** self-hosted
   runner / OIDC / SHA-deploy prose.
3. Migration: for existing children, **strip** stale "CI/CD"/"Secrets Required" sections when model is
   `local-azd` (idempotent, section-bounded edit).

### P6 — Add an orchestrator-level **e2e-tester** agent template *(Parent; azure-fullstack)*
1. New `templates/init/agents/e2e-tester.agent.md.tmpl` (parameterized): role, "when invoked",
   protocol (read topology → run `scripts/e2e-test.sh` → interpret → triage with skills → report),
   and a structured PASS/FAIL report format.
2. Install only when the pattern declares it (add `orchestrator_agents: [e2e-tester]` to `pattern.yml`).

### P7 — Strengthen specialist/critic templates *(Children; all roles)*
1. `specialist.agent.md.tmpl`: add a **"Known File Locations"** table seeded per role
   (`default_stack_for_role`), a **"Token Efficiency Rules"** block (never `find`/`ls`; batch edits;
   validate once; one build cycle per fix; get IDs from `topology.md`), and a **contract-alignment**
   reminder (read `.contracts/*.yml` first; field-name casing).
2. Make the validation line **compound** and include a `docker build` step where the role produces an image.
3. `critic.agent.md.tmpl`: convert to a focused **hard-gate / instant-FAIL checklist** and add a
   "Known exceptions" note (so documented decisions like the VNet AVM exception aren't false-flagged).
4. Keep these generic; push role specifics (MSAL gates, CRS rules, Foundry client, AVM exceptions)
   into **role-seeded snippet partials** selected by `role`.

### P8 — Role-specific seed content *(Stack role)*
Add role partials consumed by P7/P4 so each generated agent/topology carries domain knowledge:
- **frontend:** MSAL hard gates + 3-second pre-build validation snippet.
- **backend:** Entra token-validation quick reference (v1/v2 audience, JWKS URL), `slowapi` note.
- **waf:** request-flow map, OWASP CRS 911100 exclusion recipe, nginx rules, deploy-last/`min_replicas=1`.
- **agent:** Foundry client configuration reference.
- **infra:** ACA networking quick reference, documented AVM exceptions (VNet, ACR public access),
  local-azd state model.

### P9 — Pin region + small NFR hygiene *(All repos)*
1. Add `region: centralus` to `pattern.yml` (overridable in `init.yml`); thread into NFR/topology
   defaults. *(Matches the standing "all regional Azure resources → Central US" steering.)*
2. Reconcile `nfr.yml` networking/cost statements with the local-azd model (e.g. ACR
   `public_network_access_enabled=true` is required for `az acr build` — document as an explicit,
   approved exception rather than a violation).

---

## 6. Versioning & validation plan

1. Bump `VERSION`/`.framework-version` to **0.2.0** (P1/P2/P4/P5/P6 change generated output → MINOR).
2. Write `migrations/v0.1.0_to_v0.2.0.sh` covering P0 (mcp merge), P1 (skills), P2/P5 (deployment-model
   rewrite + child instruction de-stale), P4 (topology scaffold). Idempotent, bash-only, exit 0.
3. Validate with the existing harness:
   - `bash -n scripts/init.sh && bash -n scripts/init-core.sh`
   - `bash tests/test-init.sh` (fresh init produces skills/topology/child-instructions)
   - `python3` import check across `tools/*/server.py`
   - `scripts/upgrade.sh --dry-run` from a copy of a `word-game-*` repo to confirm the migration.
4. Update `README.md` + `MAINTAINING.md`: document the skills mechanism, `deployment_model`,
   `region`, and the new generated artifacts.

---

## 7. Quick reference — files to add/edit in the baseline

**Add**
- `templates/init/skills/<…>/SKILL.md(.tmpl)` (+ `templates/`) — 9 seeded skills
- `templates/init/topology.md.tmpl`
- `templates/init/child-instructions.md.tmpl`
- `templates/init/agents/e2e-tester.agent.md.tmpl`
- `templates/init/agents/_role-snippets/{frontend,backend,waf,agent,infra}.md.tmpl`
- `migrations/v0.1.0_to_v0.2.0.sh`

**Edit**
- `templates/init/mcp.json.tmpl` (+3 servers)
- `templates/init/instructions.md.tmpl` (session-init, MCP table, deployment-model gating, topology pointer)
- `templates/init/agents/specialist.agent.md.tmpl` / `critic.agent.md.tmpl` (token rules, known-files, hard gates)
- `patterns/azure-fullstack/pattern.yml` (`skills`, `deployment_model`, `region`, `orchestrator_agents`)
- `patterns/azure-fullstack/nfr.yml` (deployment-model-aware devops; region; ACR exception)
- `scripts/init-core.sh` (`install_skills`, topology render, child-instructions render, e2e-agent render)
- `VERSION`, `.framework-version`, `README.md`, `MAINTAINING.md`
