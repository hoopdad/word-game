# Decisions Log

One line per decision. Append only. Format: `YYYY-MM-DD | category: decision`

---
2026-06-17 | security: WebSocket auth uses ticket-based auth (not JWT in query params) to prevent token leakage in logs/referrers
2026-06-17 | security: Agent service is internal-only — NOT routed through WAF; only API calls agent over private networking
2026-06-17 | architecture: Single-game enforcement via Cosmos singleton control document with ETag conditional writes
2026-06-17 | architecture: Idempotent guess judgment via Cosmos ETag/version on word state documents — prevents double-scoring
2026-06-17 | architecture: Category generation has 30s hard timeout with fallback to cached/default categories on failure
2026-06-17 | security: Category URL fetching enforces scheme/IP allowlists, DNS resolution validation, size/timeout limits (SSRF prevention)
2026-06-17 | architecture: For initial dev deployment, single-replica ACA instances avoid need for WebSocket broadcast backplane; scale-out requires Redis/Web PubSub (future)
2026-06-17 | data: Cosmos partition keys designed for access patterns: users(/id), games(/id with singleton lock), scores(/userId), category_config(/id)
2026-06-17 | security: All WebSocket events validated server-side for role/state authorization (guesser can only guess, clue-givers can only judge)
2026-06-17 | architecture: Player disconnection handled with reconnect window, guesser skip/forfeit on disconnect, quorum checks
2026-06-17 | infra: GPT-4.1-mini deployed with GlobalStandard SKU in Central US (Standard SKU not supported in this region)
2026-06-17 | infra: Entra ID resources removed from Terraform — managed by scripts/setup-entra.sh (local workstation with az cli)
2026-06-17 | infra: Container App resources split from word-game-infra — each service's CD workflow creates/manages its own app via az containerapp CLI
2026-06-17 | infra: Container App Environments remain in infra TF (platform resource); individual apps are ephemeral per-deploy
2026-06-17 | devops: SHA-named container app deployment pattern — new app created per deploy (wordgame-{service}-v{sha7}), old deleted after health check
2026-06-17 | devops: WAF excluded from SHA-named pattern — deploys in-place last, reads active service FQDNs from Key Vault
2026-06-17 | devops: Single GHA app registration (ca17ff28) with per-repo federated credentials for OIDC (acceptable for initial dev; separate per trust tier for prod)
2026-06-17 | devops: CD workflows use concurrency groups to prevent race conditions between simultaneous deploys
2026-06-17 | devops: Active service FQDNs stored in Key Vault for WAF upstream discovery after SHA-named deploys
2026-06-17 | security: Cosmos data-plane access uses cosmosdb_sql_role_assignment (not ARM RBAC) with built-in Data Contributor role
2026-06-18 | architecture: word-game-agent category extraction uses agent_framework.foundry.FoundryChatClient with managed identity; agent-framework 1.8.1 exposes the required client so azure-ai-inference fallback is unnecessary
2026-06-17 | devops: azd up in word-game-harness uses Terraform provision hooks plus custom az acr build/containerapp deploy scripts because private ACR and local Terraform state do not fit azd's default service deployment flow
2026-06-17 | devops: Local azd up from word-game-harness replaces GitHub Actions/OIDC; Terraform uses local state and images build via az acr build
2026-06-18 | devops: Migrated from GitHub Actions CI/CD to local azd deployment model — single `azd up` from harness deploys all
2026-06-18 | devops: Removed OIDC federation and GHA workflows from all repos; Azure auth via local az login
2026-06-18 | devops: word-game-agent FoundryClient rewritten to use real Azure AI Inference SDK with managed identity
2026-06-18 | devops: Created deploy-local MCP tool for orchestrator-triggered deployments
2026-06-18 | quality: Session analysis found 90% token waste from repo-wide audits and background agent churn — prompts updated
2026-06-18 | infra: Moved all services to external edge CAE (salmonpond) — internal-only CAE blocked public WAF access. Backend apps use internal ingress (same-env only) within the external environment. NFR deviation: CAE is external (not internal mode) but backend apps remain unexposed. Cross-env networking (edge→internal CAE) proved infeasible due to Azure's infrastructure IP addressing. WAF nginx uses $proxy_host and http:// for intra-environment upstream routing.
2026-06-19 | data: API stores (UserStore, CategoryConfigStore) must persist to Cosmos DB — in-memory-only caused data loss on container restart (display names, category configs lost)
2026-06-19 | architecture: Category config save flow changed to async — URLs persist to Cosmos immediately, agent generation runs fire-and-forget in background task; frontend no longer blocks on agent response
2026-06-19 | feature: Profile page added — users can change display_name post-registration with same validation rules (2-20 chars, alphanumeric + spaces, unique)
2026-06-19 | deploy: API revision ActivationFailed due to missing aiohttp dependency — azure-identity async SDK requires aiohttp but it was not in requirements.txt. Added aiohttp==3.9.5. Deploy script reuses harness HEAD as image tag, so same-tag deploys don't create new ACA revisions — used unique timestamp tag to force new revision.
2026-06-19 | bugfix: Batch fix deployed — profile upsert (require_existing=False), user_joined/user_left WS broadcasts, start_game WS→REST handler, WS dispatch spread operator, 2-user guard on Start Game button, WAF agent route proxy_pass. All dispatched via MCP child-agent-runner (phase=full).
2026-06-19 | infra: Added privatelink.documents.azure.com private DNS zone + VNet link for Cosmos DB private endpoint. Without this, Container Apps resolved Cosmos FQDN to public IP which was blocked by public_network_access_enabled=false. Fix uses AVM Cosmos module private_dns_zone_resource_ids parameter.
2026-06-19 | testing: Added authenticated e2e test script (scripts/e2e-test.sh) that acquires Entra token via az CLI and exercises all API endpoints through WAF. Previous verify-deploy.sh only checked unauthenticated route reachability, missing Cosmos-backed 500 errors.
2026-06-19 | testing: Added e2e-test skill (.github/skills/e2e-test/) and e2e tester agent (.github/agents/word-game-e2e-tester.agent.md) for automated post-deploy validation.
2026-06-19 | bugfix: start_game timeout fixed — moved WS broadcast out of game lock via asyncio.create_task and bounded category-config Cosmos read with 2s wait_for, so POST /api/game/start returns well under the 10s frontend axios timeout even with a stale/dead WebSocket.
2026-06-19 | feature: Active-user presence now uses 600s inactivity TTL (PRESENCE_TTL_SECONDS=600) — ConnectionManager tracks last_seen, active_users() unions live connections with recently-seen users, disconnect no longer emits user_left; a 30s background sweeper expires inactive users and broadcasts user_left once. Dashboard polls /api/users/active every 30s to converge. Per-replica in-memory (single-replica dev model).
2026-06-19 | devops: deploy-local MCP tool fails for service-only deploys — it runs the deploy script via `bash -lc "<inlined>"` under `set -u`, so BASH_SOURCE[0] is unbound and HARNESS_DIR misresolves to /home/mike/source/word-game. Workaround: run `bash scripts/azd-deploy.sh` directly (deploys all services, auto-verifies).
2026-06-19 | devops: Fixed deploy-local MCP tool. azd-deploy.sh now accepts an optional service arg (all|api|agent|web|waf) via a should_deploy gate, making it the single source of truth. The MCP tool's single-service path now delegates to `bash scripts/azd-deploy.sh <service>` (run as a real file, so BASH_SOURCE self-location works) instead of slicing/inlining the script via `bash -lc`. This also eliminates per-service config drift (the old inlined web body used port 80 not 8080+MSAL build args; waf used 443/https not 8080/http). Removed dead _load_deploy_script_prefix/_filtered_service_script helpers.
