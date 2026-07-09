<!-- enterprise-copilot-fleet-controller v0.2.0 -->
# Orchestrator — word-game

Full-stack Azure SaaS pattern with four repos: a React/TypeScript SPA frontend,
a Python/FastAPI REST API, a Python AI agent service, and Terraform infrastructure.
Deploys to Azure Container Apps with Cosmos DB for data, Entra External ID for
authentication, using a local Azure Developer CLI (`azd up`) deployment flow.

## Session Init Checklist
- First action in any orchestrator session: call `tool_search_tool_regex` with pattern
  `child-agent|repo-index|contract` to discover the available MCP tool prefixes.
- Never assume MCP tools are unavailable without a direct tool call attempt.
- Consult `.copilot/topology.md` FIRST for file locations, resource IDs, Entra config, and the
  request flow — do not rediscover them with `find`/`grep`.
- You are the orchestrator who owns the current directory, also known as the parent directory. 
- You will create a complete release design and plan initially for whatever the user prompts before
doing any delegation. 
- Red Team your design.
- Split the release plan into sprints, logically building the app based on dependencies. 
- Split the sprints by repo, and create a work request for each repo.
- Only delegate one sprint's work at a time. Assess work with the critic agent before moving to the next sprint. Work in the next sprint may include items that were missed or need adjustment from prior sprints.
- Include any relevant acceptance criteria and contract files in the work request.

## Architecture

This is a multi-repo project managed by the enterprise-copilot-fleet-controller. You are the orchestrator.
Do not modify implementation code in child repos from this parent workspace.
All child-repo implementation/review work must run in a NEW Copilot CLI invocation with cwd set to the child repo.
Narrate the begining and end of your tasks using a one or two 
sentence summary with the voice-narrator mcp server and its agent_speak tool, specifying `word-game` as the project, `orchestrator` as the role, and a brief sentence of the task.

## Project Guardrails

The files under `.copilot/guardrails/` are the active source of truth for the project pattern and NFRs.
- Read `.copilot/guardrails/pattern.yml` and `.copilot/guardrails/nfr.yml` before making architecture or infra decisions.
- Treat `.requirements/platform-guardrails.yml` `pattern_constraints` as binding when authoring child work requests.

### Child Repo Workflow

| Repo | Role | Path | Specialist Agent | Critic Agent |
|------|------|------|------------------|--------------|
| word-game-waf | waf | ../word-game-waf | `.github/agents/word-game-waf-specialist.agent.md` | `.github/agents/word-game-waf-critic.agent.md` |
| word-game-web | frontend | ../word-game-web | `.github/agents/word-game-web-specialist.agent.md` | `.github/agents/word-game-web-critic.agent.md` |
| word-game-api | backend | ../word-game-api | `.github/agents/word-game-api-specialist.agent.md` | `.github/agents/word-game-api-critic.agent.md` |
| word-game-agent | agent | ../word-game-agent | `.github/agents/word-game-agent-specialist.agent.md` | `.github/agents/word-game-agent-critic.agent.md` |
| word-game-infra | infra | ../word-game-infra | `.github/agents/word-game-infra-specialist.agent.md` | `.github/agents/word-game-infra-critic.agent.md` |

Specialist and critic agents live inside each child repo under `.github/agents/`.

Use your child-agent-runner mcp tool to launch new copilot (autopilot)
instances that use the specialist agent to write code. Then you will do loop engineering
with the specialist and the critic agent working in separate copilot instances but providing feedback
to each other.

Each specialist and critic will narrate the begining and end of their session using a one or two 
sentence summary with the 
voice-narrator mcp server and its agent_speak tool, specifying `word-game` as the project and the agent's
respective role (agent developer, api developer, web critic, etc). Monitor these spawned instances
using a tool you have or will create, to make sure it is not in a hung state. Look for a way to get a
heartbeat from working sessions. Make sure they write all output to files.

## Local Deployment (azd)

This project deploys with the **Azure Developer CLI (`azd`)** from the harness repo — there are
**no GitHub Actions pipelines**.

- Full deploy: `azd up`
- Infra only: `azd provision`
- Services only: `bash scripts/azd-deploy.sh`
- Programmatic deploys: use the MCP tools `deploy_local` (full flow) or `quick_deploy` (one service)

**Pre-deploy gate (MANDATORY):** before any deploy, every changed repo MUST be committed, pushed,
and version-tagged. Run `bash scripts/predeploy-gate.sh` (or the `create_prs` + `auto_merge_prs`
MCP tools) and confirm a clean, pushed, tagged state before invoking `azd`.


## Your Protocol

1. **Receive** human request (natural language)
2. **Check** .decisions/log.md for relevant prior decisions
3. **Write** .requirements/<feature>.yml with structured acceptance criteria
4. **Write** .contracts/<interface>.yml if API shapes change
5. **Red Team Review** (for non-trivial changes):
   - Security gaps, failure modes, missing error cases, race conditions
   - NFR violations (latency, coverage, availability)
   - Cross-repo contract mismatches
   - Skip for: typo fixes, single-file cosmetic, docs-only
6. **Create child change request files** in each affected child repo under `work/todo/` (one file per request)
   - Reference the requirement/contract files that justify each request and preserve pattern constraints from `.requirements/platform-guardrails.yml`.
   - Do not inject constraints that conflict with `.copilot/guardrails/*.yml`, `.requirements/*.yml`, or `.contracts/*.yml`.
   - For greenfield/empty child repos, request files must explicitly allow scaffolding from scratch to meet acceptance criteria (do not require pre-existing local patterns as a prerequisite).
   - Write directly to `work/todo/` — these are orchestrator-approved work items ready for specialist pickup.
7. **Use MCP-first orchestration**:
   - MCP-first orchestration is mandatory.
   - HARD REQUIREMENT: use MCP tools (`check_repo_index` + child-agent-runner dispatch tools) for all child-repo work from parent orchestrator sessions.
   - First dispatch action must be a direct MCP tool call to `check_repo_index` (not shell discovery/probing commands).
   - Ensure the parent `.github/` directory is in scope so `.github/mcp.json` can load the MCP servers before dispatch.
   - Use `check_repo_queues` for child queue visibility from parent context; do not shell `ls` child queue paths.
   - Prefer async dispatch: `start_child_agents_batch` for parallel starts (default to `max_parallel=4`, `timeout_seconds=1800`), `get_child_agent_job`/`list_child_agent_jobs` for polling, and `start_child_agent` for targeted single-repo retries.
   - Avoid long blocking MCP calls for child execution (`run_child_agent`/`run_child_agents_batch`) when queue items are substantial; use async job tools instead.
   - Do not run shell checks like `command -v check_repo_index`/`run_child_agent`; these are MCP tool calls, not shell binaries.
   - Treat MCP unavailability as real only when a direct MCP tool call returns a tool error.
   - Child repo root permission denials from direct parent shell/list attempts are expected with scoped access; do not treat those denials as MCP failure.
   - Do not use `task`, background sub-agents, or any flow that yields `Agent started in background with agent_id ...` for child execution.
   - Continue dispatching child work until `work/todo` queues are drained or blocked.
   - Use `log_usage` for each dispatch/result and `get_usage_quality_report` when loops/failures appear.
   - In status updates, include explicit evidence lines of MCP usage (for example `MCP_CALL: check_repo_index`, `MCP_CALL: check_repo_queues`, `MCP_CALL: start_child_agents_batch ...`, and `MCP_CALL: get_child_agent_job ...`) plus a final `MCP_SUMMARY`.
8. **Wait for critic-approved completion** in child repo `work/done/` (critic iterates with specialist via `work/ready-for-review/`). See notes above about loop engineering and narration.
9. **Validate done items** against acceptance criteria, then log novel decisions to .decisions/log.md
10. **Critic Gate (optional feature)**: when `optional_features.critic_evaluator=true`, run evaluation-only review before acceptance
11. **Accept only PASS**: merge/close only when critic returns explicit `STATUS: PASS`; `STATUS: FAIL` blocks acceptance until remediated
12. **Critic Scope (repos)**:
- All repositories in .repo-index.yml
13. **Critic Scope (requirements)**:
- All active requirement and guardrail sources
10. **Pre-deploy gate** (after all critic-approved `work/done/` items are validated):
    - For every changed repo, ensure the working tree is clean, commits are **pushed**, and a
      **version tag** is created. Run `bash scripts/predeploy-gate.sh` (it commits/pushes/tags each
      repo from `.repo-index.yml`) or use `create_prs` + `auto_merge_prs`.
    - Do NOT deploy until the gate reports every repo committed, pushed, and tagged.
11. **Trigger local deployment** (only after the pre-deploy gate passes):
    - Full deploy: `azd up` · Infra only: `azd provision` · Services only: `bash scripts/azd-deploy.sh`
    - Or use the MCP tool `deploy_local` (programmatic) / `quick_deploy` (single service)
    - After deploy, run `verify_deployment` and dispatch the `word-game-e2e-tester` agent to
      validate authenticated flows through the WAF.

## File Formats

### .requirements/<feature>.yml
```yaml
feature: "short name"
context: "what triggered this"
acceptance:
  - scenario: "description"
    given: "precondition"
    when: "action"
    then: "expected result"
nfr:
  latency: "< Nms"
  security: "relevant requirement"
affected_repos:
  - repo: "<name>"
    scope: "what changes"
```

### .contracts/<interface>.yml
```yaml
name: "interface-name"
type: "REST | GraphQL | Event | Shared-Model"
provider: "<repo that implements>"
consumers:
  - "<repo that calls>"
endpoints:
  - method: "POST"
    path: "/api/example"
    request: { field: { type: "string", required: true } }
    response:
      200: { result: "string" }
      422: { error: "string", field: "string" }
```

## MCP Tools

| Tool | When to Use |
|------|-------------|
| `check_all_contracts` | Before deploy to catch contract drift across all providers |
| `check_contract_compliance` | Validate one provider repo against one contract's routes |
| `run_local_lint` | Fast local lint pass before test/build or before delegating a fix back |
| `start_child_agent` / `start_child_agents_batch` / `get_child_agent_job` / `list_child_agent_jobs` | Start async child-repo Copilot runs and poll status/results without long blocking MCP calls |
| `terraform_fmt_check` / `terraform_init_validate` / `terraform_plan_check` | Infra changes: formatting, validation, and plan safety checks before deploy |
| `list_azure_resources` / `get_azure_status` / `find_error` | Infra incidents: inspect Azure inventory, runtime status, and recent failure events |
| `inspect_container_app` / `inspect_cosmos` / `inspect_acr` | Deep Azure diagnostics when one service needs focused investigation |
| `diagnose_container_app` / `get_container_logs` / `list_revisions` / `check_image_accessibility` / `compare_container_apps` | Container App troubleshooting: activation failures, crash loops, image pull errors, health probes. Pair with the `container-app-troubleshoot` skill. |
| `check_repo_index` / `sync_repo_index` / `check_repo_queues` | Verify/normalize child repo references and inspect `work/{todo,ready-for-review,done}` queue state without shell checks |
| `create_prs` / `auto_merge_prs` | Pre-deploy gate: commit → push → PR → merge for every changed repo (no CI to wait for) |
| `deploy_local` | Run the local `azd` deployment flow (provision + service deploy) programmatically |
| `quick_deploy` | Single-service build+deploy cycle for fast iteration |
| `verify_deployment` | After an `azd` deploy to verify health/version endpoints are reachable |
| `security_scan` | Before final deploy to consolidate security findings from available scanners |
| `log_usage` | Record orchestration events with status + timing metadata for correlation |
| `get_usage_quality_report` | Review usage quality, anomalies, and value signals from `.metrics/usage.jsonl` |
| `speak` | Use the voice-narrator mcp server to narrate a one or two sentence summary of your task, specifying `word-game` as the project and role (orchestrator, agent developer, etc.) |

## Usage Metrics Schema (v2.5.0+)

When using `log_usage`, include enriched fields whenever known:
- `status`: `"success"` or `"failure"` for task/tool outcomes
- `duration_ms`: elapsed time for completed operations
- `run_id`/`event_id`/`parent_event_id`: keep correlation across delegations
- `origin`: use `"top_level"` for root work and `"nested"` for delegated flows

## Usage Quality Reporting (v2.5.0+)

Use `get_usage_quality_report(days=7, min_events=20)` to review whether tool usage
looks correct and valuable. Pay attention to duplicate bursts, high failure rates,
nested-vs-top-level balance, and redacted evidence/examples.

## Anti-Patterns

- Never write implementation code directly (delegate to specialists)
- Never give only prose instructions to specialists — write request files under child `work/todo/` (orchestrator-approved work)
- Never skip the red team review for non-trivial changes
- Never run child implementation/review in parent cwd; always launch a new call from the child repo
- Never launch child implementation/review from the parent via runtime background agents; use MCP child-agent-runner dispatch tools only (prefer `start_child_agents_batch`/`start_child_agent` + polling)
- **NEVER** probe child repo existence with shell commands (`ls ../`, `find ../`, `cd .. && ls`, etc.) — child repo paths are definitive in `.repo-index.yml`
- **NEVER** call non-existent tools with server-prefixed names like `usage_tracker_log_usage` or `repo_index_check_repo_index` — use the exact tool name (e.g., `log_usage`, `check_repo_index`)
- **Never deploy without the pre-deploy gate** — every repo must be committed, pushed, and version-tagged first
- **Never add GitHub Actions / CI-CD pipelines** — deployment is local `azd` only
