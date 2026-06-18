<!-- enterprise-copilot-fleet-controller v0.1.0 -->
# Orchestrator — word-game

Full-stack Azure SaaS pattern with four repos: a React/TypeScript SPA frontend,
a Python/FastAPI REST API, a Python AI agent service, and Terraform infrastructure.
Deploys to Azure Container Apps with Cosmos DB for data, Entra External ID for
authentication, and local azd deployment from word-game-harness.

## Architecture

This is a multi-repo project managed by the enterprise-copilot-fleet-controller. You are the orchestrator.
Do not modify implementation code in child repos from this parent workspace.
All child-repo implementation/review work must run in a NEW Copilot CLI invocation with cwd set to the child repo.

## Project Guardrails

The files under `.copilot/guardrails/` are the active source of truth for the project pattern and NFRs.
- Read `.copilot/guardrails/pattern.yml` and `.copilot/guardrails/nfr.yml` before making architecture or infra decisions.
- Treat `.requirements/platform-guardrails.yml` `pattern_constraints` as binding when authoring child work requests.
- If they require Azure Verified Modules, treat that as mandatory whenever an AVM exists.
- If no AVM exists for a required Azure service, record the exception in `.decisions/log.md` before approving a native resource fallback.

### Child Repo Workflow

| Repo | Role | Path | Specialist Agent | Critic Agent |
|------|------|------|------------------|--------------|
| word-game-waf | waf | ../word-game-waf | `.github/agents/word-game-waf-specialist.agent.md` | `.github/agents/word-game-waf-critic.agent.md` |
| word-game-web | frontend | ../word-game-web | `.github/agents/word-game-web-specialist.agent.md` | `.github/agents/word-game-web-critic.agent.md` |
| word-game-api | backend | ../word-game-api | `.github/agents/word-game-api-specialist.agent.md` | `.github/agents/word-game-api-critic.agent.md` |
| word-game-agent | agent | ../word-game-agent | `.github/agents/word-game-agent-specialist.agent.md` | `.github/agents/word-game-agent-critic.agent.md` |
| word-game-infra | infra | ../word-game-infra | `.github/agents/word-game-infra-specialist.agent.md` | `.github/agents/word-game-infra-critic.agent.md` |

Specialist and critic agents live inside each child repo under `.github/agents/`.

## Local Deployment

- Full deploy: `cd word-game-harness && azd up`
- Infra only: `azd provision`
- Services only: `bash scripts/azd-deploy.sh`
- Programmatic deploys: use the MCP tool `deploy-local`


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
8. **Wait for critic-approved completion** in child repo `work/done/` (critic iterates with specialist via `work/ready-for-review/`)
9. **Validate done items** against acceptance criteria, then log novel decisions to .decisions/log.md
10. **Critic Gate (optional feature)**: when `optional_features.critic_evaluator=true`, run evaluation-only review before acceptance
11. **Accept only PASS**: merge/close only when critic returns explicit `STATUS: PASS`; `STATUS: FAIL` blocks acceptance until remediated
12. **Critic Scope (repos)**:
- All repositories in .repo-index.yml
13. **Critic Scope (requirements)**:
- All active requirement and guardrail sources
10. **Trigger local deployment** (after all critic-approved `work/done/` items are validated):
    - Run `cd word-game-harness && azd up` for a full deployment
    - Run `azd provision` when only infrastructure must be applied
    - Run `bash scripts/azd-deploy.sh` when only services must be rolled out
    - Use the MCP tool `deploy-local` for programmatic deployment and verify the reported result

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
| `check_all_contracts` | Before merge to catch contract drift across all providers |
| `check_contract_compliance` | Validate one provider repo against one contract's routes |
| `run_local_lint` | Fast local lint pass before test/build or before delegating a fix back |
| `start_child_agent` / `start_child_agents_batch` / `get_child_agent_job` / `list_child_agent_jobs` | Start async child-repo Copilot runs and poll status/results without long blocking MCP calls |
| `terraform_fmt_check` / `terraform_init_validate` / `terraform_plan_check` | Infra changes: formatting, validation, and plan safety checks before PR |
| `list_azure_resources` / `get_azure_status` / `find_error` | Infra incidents: inspect Azure inventory, runtime status, and recent failure events |
| `inspect_container_app` / `inspect_cosmos` / `inspect_acr` | Deep Azure diagnostics when one service needs focused investigation |
| `diagnose_container_app` / `get_container_logs` / `list_revisions` / `check_image_accessibility` / `compare_container_apps` | Container App troubleshooting: activation failures, crash loops, image pull errors, health probe failures. Use the `container-app-troubleshoot` skill for guided triage. |
| `check_repo_index` / `sync_repo_index` / `check_repo_queues` | Verify/normalize child repo references and inspect `work/{todo,ready-for-review,done}` queue state without shell checks |
| `deploy-local` | Trigger the local azd deployment flow programmatically from word-game-harness |
| `verify_deployment` | After local azd deployment to verify health/version endpoints are reachable |
| `security_scan` | Before final merge/deploy to consolidate security findings from available scanners |
| `orchestrate_release` / `create_prs` / `wait_for_ci` / `auto_merge_prs` | Multi-repo release flow when coordinating commit→PR→review→merge handoff before local deployment |
| `log_usage` | Record orchestration events with status + timing metadata for correlation |
| `get_usage_quality_report` | Review usage quality, anomalies, and value signals from `.metrics/usage.jsonl` |

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
