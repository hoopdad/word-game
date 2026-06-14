# OPERATOR_RUNBOOK

This is the canonical quality-gates runbook for this repository.

## Operating workflow

- Read `.github/copilot-instructions.md` and this runbook before starting repo work.
- Query open todos first; treat SQL as the source of truth for task state.
- If no todos exist, create a dependency-aware todo graph that maximizes parallelism.
- Dispatch independent ready todos in parallel; serialize only true dependency chains.
- Reconcile agent-reported status vs SQL todo status before each new dispatch cycle.
- Check out or create a feature branch before changing files.
- Keep repo artifacts under `work/` and use `plan.md` for multi-step tasks.
- Use `scripts/verify-local.sh` for the standard local check. If it doesn't exist on the first run, create it.
- Use `scripts/watch-workflow.sh CI pull_request <branch>` to monitor PR CI. If it doesn't exist on the first run, create it.
- Use `scripts/watch-workflow.sh CD push main` to monitor post-merge CD. If it doesn't exist on the first run, create it.
- After local verification, push, open a PR, and monitor the CI workflow.
- After merge, monitor the CD workflow and troubleshoot failures in place.
- On todo completion or blockage, update SQL status immediately.

## Efficiency gate

- Prefer filesystem event-driven flows over polling.
- Current Android auth persistence path (`TokenStore` + `KeyValueStore`) does not use a filesystem polling loop.
- If polling is introduced later, require adaptive backoff and bounded cleanup before release.

## Persistence gate

- Session state is written atomically through `KeyValueStore.putAtomic(...)`.
- Sensitive token state is integrity-protected with a SHA-256 checksum.
- Startup replay is required: persisted session data must be readable by a fresh process instance (`TokenStore` restart test coverage).

## Clarity gate

- Keep this file (`docs/runbooks/OPERATOR_RUNBOOK.md`) as the canonical operator runbook.
- Keep instructions in `.github/copilot-instructions.md` concise and durable.
- Emit per-task timeline artifacts under `work/timeline/<correlation_id>.jsonl`.
- Each JSONL line should represent a single timestamped event in task execution.
- Keep sprint critic reports under `work/sprint-review/critic-<timestamp>.md`.
- Keep operational artifacts under `work/` paths.

## CI/CD Verification gate (CRITICAL)

**Rule: No task is complete until required CI/CD workflows for that change set are verified on GitHub Actions.**

Local builds do NOT guarantee CI/CD success. CI runs linting, tests, and deployment checks that may fail for environment reasons. CD runs release/deployment steps that may fail independently.

### Changed-file gating behavior (CI)

- CI workflow trigger (`.github/workflows/ci.yml`) ignores PRs that change only:
  - `README.md` / `**/README.md`
  - `.github/workflows/**`
- For PRs where CI does run, jobs are gated by changed files:
  - Web job: `apps/web/**`
  - API job: `apps/api/**`
  - Agent job: `apps/agent/**`
  - Infra validate job: `infra/**`
  - Shared/tooling fan-out: `packages/shared/**`, `scripts/**`, `package.json`, `package-lock.json`
- Operator expectation:
  - README/workflow-only PRs: CI may be skipped by design.
  - Mixed PRs: workflow can run but component jobs may be skipped if no matching files changed.

### Deployment ordering behavior (CD)

- CD workflow (`.github/workflows/cd.yml`) runs on `push` to `main` or manually via `workflow_dispatch`.
- Infrastructure deploy is the first gate and must succeed before any app service deploy starts.
- App service deploy jobs (`web`, `api`, `agent`) all depend on `infra-deploy`.
- Default deployment region is `centralus` unless `AZURE_LOCATION` or manual input overrides it.

### Post-commit CI/CD verification checklist

After pushing code to remote, ALWAYS verify:

1. **Push all branches to remote**
   ```bash
   git push origin <branch>
   ```

2. **Monitor workflow status**
   ```bash
   gh run list --limit 5 --json status,conclusion,name,createdAt --jq '.[] | "\(.name) - \(.status) - \(.conclusion)"'
   ```

3. **Wait for required workflows/jobs to show `"status": "completed"`**
   - If CI is skipped by design due to changed-file gating, record that outcome and continue with applicable gates.
   - For code-touching changes, do NOT proceed until required CI jobs reach "completed" status.
   - Check every 10 seconds if not using watch script

4. **Verify required workflows/jobs show `"conclusion": "success"`**
   ```bash
   # Expected output:
   # CI - completed - success
   # CD - completed - success
   ```

5. **If any required workflow/job shows failure, investigate immediately**
   ```bash
   # Get the most recent run's full log
   gh run view $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId') --log
   
   # Filter for errors
   gh run view $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId') --log | grep -A 5 -B 5 -i "error\|fail"
   ```

### Automated monitoring script

Use this command to watch until completion:

```bash
for i in {1..120}; do 
  result=$(gh run list --limit 1 --json status,conclusion,name | jq '.[] | "\(.name): \(.status) \(.conclusion)"'); 
  echo "[$(date +%H:%M:%S)] $result"; 
  if echo "$result" | grep -q "completed success"; then 
    echo "✅ WORKFLOW SUCCESS"; 
    break; 
  elif echo "$result" | grep -q "completed failure"; then 
    echo "❌ WORKFLOW FAILED"; 
    break; 
  fi; 
  sleep 10; 
done
```

### Common failure patterns to investigate

- **Node workspace failures**: dependency drift or lockfile mismatch (`npm ci` errors)
- **Path-filter misses**: expected job skipped because changed file pattern did not match
- **Terraform failures**: provider init/auth/backend issues in `infra` stage
- **OIDC auth failures**: missing/misconfigured `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, or federated credential subject mismatch
- **Container deploy failures**: ACR push errors, `az containerapp update` target name/resource-group mismatch

### Auth remediation playbook (Android app flow)

- **Microsoft `AADSTS500113` / reply URL errors**
  - Symptom: Microsoft auth fails with reply URL/redirect URI language.
  - App behavior maps these to a targeted message instructing Azure registration of the exact reply URL.
  - Operator action: register the exact `msauth://<package>/<signature-hash>` value in Azure App Registration → Authentication (Mobile and desktop applications).

- **Google `DEVELOPER_ERROR` / app misconfiguration**
  - Symptom: Google sign-in returns `DEVELOPER_ERROR`.
  - Typical root causes: OAuth package/signing cert mismatch, wrong Web client ID, stale `google-services.json`.
  - Operator action: validate Android OAuth client package + signing certs, align Web client ID to the same project, and refresh `google-services.json`.

### Staged orchestration + bounded remediation loop

- Auth flow is staged: `Stage0Bootstrap` → `Stage1ProviderPreflight` → `Stage2InteractiveAuth` → `Stage3PostAuthStabilization` → `Stage4NavigationCommit` → `TerminalFailure`.
- Bounded retry/stop controls:
  - `MAX_PROVIDER_ATTEMPTS = 2`
  - `MAX_GLOBAL_ATTEMPTS = 3`
  - `MAX_PREFLIGHT_RECHECKS = 1`
  - `MAX_NAV_COMMIT_RETRIES = 1`
  - `GLOBAL_TIMEOUT_MS = 90_000`
- Preflight blocks the flow when both providers are blocked (`GATE_G1_FAILED`), and retry-preflight is intentionally capped; once exhausted, remediation is required before another attempt.
- Interactive attempts terminate on retry-budget exhaustion, repeated non-retryable errors, repeated user cancels, or global timeout, so operator remediation is bounded and correlation-ID-driven.

### Rule: Update SQL status AFTER CI/CD pass

Do NOT update todo status to `done` until:
- Required CI/CD workflows/jobs for the change set are verified (`success`/completed), or explicitly skipped by changed-file gating.
- You have visually verified with `gh run list`

If failure occurs, update status to `blocked` and document the error in the todo description.

## Definition of done for sprint close

- All sprint todos are `done` in SQL.
- All code is pushed to a remote feature branch unless deployment is required.
- If deployment is required, code is on `main`, the feature branch is deleted, and local source is updated to latest remote state.
- Release gate passes.
- **CI/CD gate passes**: Required CI/CD workflows/jobs for the change set show `conclusion: "success"` (or are intentionally skipped by gating), verified with `gh run list`
- Critic confirms all four quality gates pass with no must-fix findings, documented in `work/sprint-review/critic-<timestamp>.md`.

## Sub-agent workflow

- Read the handoff artifact first, if present.
- Do not rediscover repository layout if the handoff already provides it.
- Only search for information the handoff says is still unknown.
- Never use `**/*` broad glob searches.
- **On code push: Do NOT mark todo as done until CI/CD passes**
  - Wait for required workflows/jobs to reach `status: "completed"` (or confirm intentional changed-file skip)
  - Verify required workflows/jobs show `conclusion: "success"`
  - Use: `gh run list --limit 1 --json status,conclusion,name`
  - If failure, investigate and fix before marking done
  - Do NOT mark todo as done if CI/CD failed
- On success: `UPDATE todos SET status = 'done' WHERE id = '<todo-id>'`
- On blocked: `UPDATE todos SET status = 'blocked' WHERE id = '<todo-id>'`
- Return completed work, done/not-done, and blockers/questions.
