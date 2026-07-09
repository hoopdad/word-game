# Decisions Log

One line per decision. Append only. Format: `YYYY-MM-DD | category: decision`

---

2026-07-08 | bootstrap: child repos (waf/web/api/agent/infra) are greenfield/empty at init (GitHub remotes report empty repos); contracts + decisions below are derived from .copilot/topology.md and init-pattern.yml app_description, not from committed source
2026-07-08 | game: single active game globally — only one game runs in the entire system at a time
2026-07-08 | game: anyone loading the site before a game starts can join; roles are one guesser + N clue-givers
2026-07-08 | auth: Entra External ID (MSAL) for the SPA; API validates v2.0 JWT bearer tokens
2026-07-08 | auth: API scope is api://<api-client-id>/access_as_user; token sent as Authorization: Bearer header
2026-07-08 | auth: SPA uses acquireTokenPopup, never acquireTokenRedirect (avoids infinite redirect loops)
2026-07-08 | auth: MSAL redirectUri = window.location.origin at runtime (NOT a VITE_* build var); SPA redirect URI is WAF FQDN + /welcome
2026-07-08 | api: request/response bodies use snake_case (Python/Pydantic convention)
2026-07-08 | api: validation errors return HTTP 422 with { error, field }; auth failures return 401, authorization failures 403
2026-07-08 | api: GET /health returns 200 (unauthenticated smoke endpoint used by e2e/verify)
2026-07-08 | realtime: multiplayer sync uses WebSocket at /ws/* served by word-game-api (:8000)
2026-07-08 | routing: WAF is the single public entry (:443) — /* -> web:80, /api/* + /ws/* -> api:8000, /agent/* -> agent:8000
2026-07-08 | waf: min_replicas = 1 (public entry point must not scale to zero)
2026-07-08 | waf: OWASP CRS via ModSecurity; exclude rule 911100 for /api/* to allow PUT/PATCH/DELETE; nginx map_hash_bucket_size = 128
2026-07-08 | agent: Python AI agent uses Microsoft Agent Framework + Azure AI Foundry client (GPT-4.1-mini or higher) for analytical/decision functions; stateless, exposed via POST /agent/*
2026-07-08 | data: Cosmos DB is the datastore for authoritative game state
2026-07-08 | infra: Terraform IaC (local state) — AVM-first modules; record an exception in this log before any native-resource fallback
2026-07-08 | infra: ACR public_network_access_enabled = true so images build via `az acr build`
2026-07-08 | deploy: local `azd up` flow only — no GitHub Actions/CI-CD pipelines
2026-07-08 | deploy: pre-deploy gate is mandatory — commit + push + version-tag every changed repo (scripts/predeploy-gate.sh) before `azd`
2026-07-08 | sprint1: COMPLETE — all 5 repos critic-approved (work/done). infra full AVM-first platform (spoke 10.1.0.0/16, NSG deny-by-default x4 subnets, ACR, Cosmos serverless/Session, KV, LAW, internal CAE, UAMI, Foundry+GPT-4.1-mini GlobalStandard); ADR-001..008 logged in infra repo. api/agent/web/waf skeletons with /health+/version 0.1.0, multi-stage non-root containers, WAF OWASP CRS routing (911100 excluded for /api/*)
2026-07-08 | contracts: web-api-game + agent-analysis game/WS endpoints intentionally deferred to sprints 2-3 (sprint1 = skeleton only); waf-ingress + auth-entra are Gateway/Shared-Model (no REST endpoints section)
2026-07-08 | sprint2: COMPLETE — api identity+dashboard (Entra JWT validation auth.py; users store; name 422-malformed vs 409-taken; presence TTL; games-count; leaderboards top10/top3; profile; GET /api/dashboard, /api/users/active, /api/me; POST+PUT /api/users/name) at 0.2.0; web login+name-gate+dashboard+profile (NameGate, Dashboard, Profile, lib/api.ts) at 0.2.0
2026-07-08 | ops: child-agent-runner MCP server crashed mid-session (Transport closed, server.py process gone). Recovered via prescribed fallback: fresh `copilot -p <full-phase prompt> --allow-all-tools --autopilot --no-ask-user --stream on --model auto --add-dir <repo>` with cwd=child repo (faithful replica of the tool). Logs under session files/logs/
2026-07-08 | contract: extended web-api-game.yml with identity/dashboard endpoints (/api/me, /api/users/name GET-set/PUT-change, /api/users/active, /api/dashboard)

## Sprint 3 — Game Engine + Real-time (2026-07-08)
- **word-game-api @0.3.0**: single global game (Cosmos singleton + ETag optimistic concurrency;
  ETag active from first create), full game endpoints incl. `GET /api/game` (word hidden from
  guesser via `safe_game_view()`), `POST /api/game/ws-ticket` (short-lived WS auth ticket — no
  bearer in URL), `/api/categories/config` (async non-blocking persist), `/ws/game` ConnectionManager
  with `state_sync`/`game_in_progress`, role rotation (one guesser/round, covers all), 10pt scoring
  with idempotent guess (`last_guess_word_index`), 3s reveal. 68 tests pass. Critic PASS.
  Contract: 15/15 (checker mis-flags empty-path `GET /api/game` under prefix — verified present).
  Single-replica WS channel documented (`work/single-replica-note.md`, Redis backplane upgrade path).
- **word-game-agent @0.3.0**: `/agent/generate-categories` (parallel fetch, SSRF guards reject
  private/loopback/link-local/metadata IPs, size+timeout bounds), 30s hard cap + default-category
  fallback (`used_fallback`), plus generate-word/evaluate-guess/score-clue. 5/5 contract. Critic done.
- **word-game-web @0.3.0**: Configure-Categories screen (non-blocking save), lobby/join/start, WS
  client via ticket (no token in URL), role-aware round UI (guesser never shown the word),
  countdown/reveal/scoreboard/winners, reconnect via state_sync. Critic PASS.
- Contracts extended pre-dispatch: agent-analysis (+generate-categories), web-api-game
  (+categories/config), web-api-realtime (+full game-flow server events).
- Ops: child-agent-runner MCP crashed again on dispatch (Transport closed); used prescribed
  launch-child.sh fallback (new Copilot CLI invocation per child repo, cwd=repo).

## Sprint 4 — Deploy Tooling (2026-07-08)
- Authored orchestrator-owned harness deploy tooling (script-driven, NOT azd-native services):
  - `scripts/setup-entra.sh` — idempotent SPA + API app registrations, access_as_user scope,
    SPA→API delegated permission, writes `.azure/entra.json`. Default signInAudience
    AzureADandPersonalMicrosoftAccount (personal MSA self-registration) — override via env.
  - `scripts/azd-deploy.sh [all|api|agent|web|waf]` — terraform apply → tf-outputs.json →
    az acr build (4 images) → az containerapp create/update (agent→api→web→waf) → poll running →
    finalise SPA redirect URIs + API CORS with live WAF FQDN → write `.azure/deploy.json`.
    Image tag = harness short SHA (+timestamp if dirty) so same-commit redeploys get a new revision.
  - `scripts/verify-deploy.sh` — smoke test through the WAF (health, SPA root, /api/me 401 unauth,
    /agent/health).
  - `azure.yaml` — descriptor + hooks routing azd provision/deploy/up through the scripts.
- Deploy contract discovered from infra outputs + service code (recorded in topology.md):
  RG `rg-word-game-dev`, CAE `cae-word-game-dev` (internal LB), Cosmos db `wordgame` (overrides api
  default `word-game`), apps run under the UAMI. Intra-CAE via app short-names:80 + allow-insecure.
- Container Apps are created by the deploy script (Terraform provisions platform only).
- OPEN (needs @hoopdad): (1) confirm real Azure provision+deploy now (cost, correct sub/tenant, VPN);
  (2) Entra auth model (personal-MSA /common vs Entra External ID); (3) pre-deploy gate push target
  (push to main vs PR flow). Child repos: web is not yet a git repo; others have no origin remote.

## Sprint 4b — Private WAF re-networking + deploy (2026-07-09)
- DECISION (product-owner directive): WAF must be PRIVATE. Chose internal Container Apps
  Environment (`internal_load_balancer_enabled=true`) fronted by a hub-and-spoke topology rather
  than a public CAE. The `word-game-waf` app keeps `external` ingress, but on an internal CAE that
  resolves to the private LB IP (10.0.13.193) — reachable only over VNet/VPN. web/api/agent are
  internal-only (`.internal.` FQDNs).
- DECISION: re-CIDR the spoke VNet from the non-routable 10.1.x.x block to routable **10.0.12.0/22**
  (hub 10.0.0.0/22; existing spokes at 10.0.7/24, 10.0.11/24, 10.0.40/22 — 10.0.12.0/22 free) so it
  can peer with the existing hub `mikeo-lab-hub-vnet` (sub 0ff111e2, rg mikeo-lab-rg). Subnets:
  cae 10.0.12.0/23, pe 10.0.14.0/24, ingress 10.0.15.0/25, reserved 10.0.15.128/25.
- DECISION: private DNS zones live in the HUB only (linked to the spoke), none in the spoke — avoids
  duplicate-zone/link conflicts and centralises resolution. Cosmos/KV PE zone-groups point at the
  hub zone IDs via `cosmos_private_dns_zone_id` / `keyvault_private_dns_zone_id` var defaults.
- PATTERN: internal-CAE app FQDNs do NOT resolve via the generic `privatelink.azurecontainerapps.io`
  zone. Each internal CAE has a unique default domain; created a hub private DNS zone named exactly
  that domain (`victoriousdesert-ca89600e.centralus.azurecontainerapps.io`) with a wildcard `*` A →
  CAE staticIp, linked to hub + spoke. This is what makes `word-game-waf.<domain>` resolve over VPN.
- PATTERN: gateway-transit bootstrap ordering solved with `spoke_use_remote_gateways` var — apply
  spoke→hub peering with `=false` first, create hub→spoke peering (`allow_gateway_transit=true`),
  then flip to `true`. TF default is now `true` so steady-state `azd up` is idempotent.
- GOTCHA: can't change VNet/subnet address ranges in-place while PEs hold old IPs → targeted destroy
  of the network layer (PEs+subnets+NSG assoc+VNet), then apply. Cosmos/Foundry/ACR/KV/UAMI accounts
  are not IP-bound and were preserved (no data loss).
- GOTCHA: `ManagedEnvironmentCapacityHeavyUsageError` (centralus AKS capacity) is transient — delete
  the Failed CAE (ScheduledForDelete ~3min), then retry apply. User requires Central US.
- STATUS: all 4 apps Succeeded/Running (min-replicas=1); infra pushed be00d95 + tagged v0.4.0.
  App/data-plane E2E deferred until VPN restored (user disabled VPN 2026-07-09).

## Release r2 — Bugfix + UI overhaul (2026-07-10)
- CONTEXT: product owner reported 4 runtime defects on the deployed private-WAF env + "extremely
  plain" UI. Diagnosed management-plane only (VPN/data-plane off). See .requirements/r2-bugfix-ui.yml.
- ROOT CAUSES (confirmed in source):
  1. Landing "API not available": SPA calls GET /health; the WAF proxies only /api/* to the api, so
     /health hits the WEB app. FIX: add unauth GET /api/health (api) + JWTMiddleware exemption; SPA
     calls /api/health. Keep /health + /version for container probes.
  2. "Failed to load dashboard": dashboard.py (5x) + users.py (2x) pass enable_cross_partition_query=
     True to query_items() — invalid kwarg in azure.cosmos.aio -> 500. FIX: remove the kwarg (async
     SDK is cross-partition by default).
  3. Profile save 500: users.py writes to Cosmos container `name_reservations`, never provisioned.
     FIX (infra): provision name_reservations (partition /id).
  4. "Failed to load categories": categories.py uses container `config`; infra provisions
     `category_config`. Persistence broken. FIX (api): use category_config. Web<->api field mismatch
     (web {categories} vs api {websites}). FIX (web): align to api `websites` URL model.
- DECISION (categories semantics): categories are GENERATED from a configurable list of source
  website URLs (matches agent + SSRF validation + contract). Keep the URL model; align web to it;
  keep the page named "Configure Categories". Revisit if owner wants free-text category names.
- DECISION (NSG): remove `deny-internet-inbound` from word-game-infra/networking.tf (product-owner
  request). It pre-empts the lower-priority allow-vnet-inbound (VirtualNetwork) that the VPN P2S
  client range needs. SAFE: default DenyAllInBound (65500) still blocks the internet; only the WAF
  app is reachable, and only over the private LB (VPN). Zero-trust preserved.
- RED TEAM:
  * /api/health exemption must be an EXACT path match (not a prefix) so it can't be used to bypass
    auth on /api/health-anything; every other /api/* stays authenticated. (acceptance-tested)
  * Removing enable_cross_partition_query must not change result semantics — async SDK already does
    cross-partition; verify queries still return the same rows (unit tests with a Cosmos stub).
  * name_reservations partition key must be /id (reservation doc id == the normalized name key;
    delete uses partition_key=old_key). Mismatch would 500 on delete of the previous name.
  * Categories field switch is a cross-repo contract change — api + web must land together; contract
    web-api-game.yml updated (GET/PUT categories use `websites`; active_users uses `active_users`;
    added /api/health).
  * UI overhaul must NOT reintroduce XSS (all user names via JSX, no dangerouslySetInnerHTML) and
    must keep MSAL popup (never redirect), version-next-to-name, and WAF-relative /api,/ws paths.
  * No data-plane verification this session — post-deploy validation limited to revisions
    Healthy/Running + clean container logs; functional E2E deferred to owner's next VPN session.
- SPRINTS: A = api + infra (correctness/security, dispatch in parallel). B = web (contract-align
  bugfixes + full UI overhaul). B depends on A's contract. Dispatch A, critic-approve, then B.

## r2 RELEASE — DEPLOYED (2026-07-09) ✅ (management-plane verified)
- Sprints A (api+infra) and B (web) all critic-PASS. Web done directly by orchestrator after the
  child specialist stalled (0 on-disk writes); code-review critic gate returned STATUS: PASS.
- Pre-deploy gate PASSED: api v0.1.1, web v0.1.1, infra v0.4.1, harness v0.1.3 committed+pushed+tagged
  (waf v0.2.0, agent v0.1.0 unchanged). Image tag df5ca6b.
- INFRA: targeted `terraform apply -target=name_reservations` ONLY (created the missing Cosmos
  container, PK /id). Deliberately did NOT apply unrelated pre-existing drift the full plan showed
  (foundry+cosmos local_auth false->true, CAE Consumption workload_profile removal, subnet
  default_outbound_access flip) to avoid collateral damage / security regression with no data-plane
  to verify. Confirmed post-apply: cosmos disableLocalAuth still true, publicNetworkAccess Disabled.
  NSG deny-internet-inbound removal already reconciled (not in plan change set).
- SERVICES: SKIP_PROVISION=1 azd-deploy api then web. entra.json rebuilt from live app IDs
  (API db1f76a1…, SPA 87a2ac26…, tenant d52a6857) — reused existing regs, no dup. SPA redirect URIs
  + API CORS finalized to WAF FQDN.
- VERIFY (management-plane): api--0000002 + web--0000001 Active/Running, 1 replica, clean boot
  (0 ERROR/CRITICAL/Traceback). API reaches Cosmos over private PE; cross-partition queries return
  200 — validates the enable_cross_partition_query removal. NOTE: a startup warmup burst of
  cross-partition queries logs Cosmos 400 substatus 1004 then auto-retries to 200 (normal async SDK
  cross-partition execution: POST->400->GET pkranges->POST->200); settles to quiet (no hot loop).
- DEFERRED (needs owner VPN / data plane): functional E2E — profile save (name_reservations write),
  categories persist (websites), dashboard games_played, /api/health through WAF, and the new UI —
  at https://word-game-waf.victoriousdesert-ca89600e.centralus.azurecontainerapps.io

## DRIFT RESEARCH — terraform config vs. live (2026-07-09) — deep analysis, ALZ-governance root cause
Context: the r2 targeted apply revealed 7 config-vs-live diffs unrelated to r2. The product owner
asked for deep research into WHY the drift exists and which items are strategic. Investigation
(git blame, live az reads, RG/sub/MG policy survey) yields: the drift is dominated by **Azure
Landing Zone (ALZ) management-group governance**, NOT by accidental config rot. The subscription
(add4d87f…) sits under an ALZ MG hierarchy (alz → corp/connectivity/decommissioned + hoopdad MGs).
The **corp** MG assigns "Public network access should be disabled for PaaS services", "Configure
Azure PaaS services to use private DNS zones", "Deny network interfaces having a public IP"; the
**alz** MG assigns the "Microsoft Cloud Security Benchmark" + Defender initiatives. These enforce a
hardened baseline that overrides the app's TF. PROOF of active enforcement: the r2 `terraform apply`
reported Cosmos `local_authentication_enabled false→true`, yet live **stayed** `disableLocalAuth=true`
— an audit-only setting would have flipped; a Modify/Deny control held it. No RG- or sub-scoped
assignment explains it, confirming MG-scope origin.

Classification (config → live; LIVE is the more-secure/governance-enforced state in every strategic case):

| # | Drift (config → live)                                   | Root cause                                                              | Strategic? | Remediation (config edit — NO deletion)                                    |
|---|---------------------------------------------------------|------------------------------------------------------------------------|------------|-----------------------------------------------------------------------------|
| 1 | Cosmos local_authentication_enabled: true → false       | ALZ/MCSB governance disables local (key) auth; app uses AAD/UAMI        | YES (sec)  | set `local_authentication_enabled = false` in cosmos.tf (was true since S1) |
| 2 | Foundry local_auth_enabled: (default true) → false      | ALZ/MCSB governance disables Cognitive Services key auth; app uses Entra| YES (sec)  | add `local_auth_enabled = false` in foundry.tf                              |
| 3 | Subnet default_outbound_access_enabled ×4: (true)→false | Azure platform default-outbound retirement; live already zero-trust     | YES (net)  | add `default_outbound_access_enabled = false` to all 4 subnets              |
| 4 | CAE workload_profile [Consumption]: present → undeclared | azurerm reads the implicit Consumption profile on a Consumption-only env| NO (cosmetic) | declare `workload_profile{name="Consumption" workload_profile_type="Consumption"}` OR `lifecycle{ignore_changes=[workload_profile]}` |

KEY CONCLUSIONS:
- **No drift requires any resource deletion.** All 4 items reconcile by aligning TF config to the
  (secure, governance-enforced) live state. Applying the fixes is a NO-OP on live infrastructure —
  it only stops terraform from proposing to un-harden the resources.
- Items 1–3 are STRATEGIC: codifying them prevents a future `azd provision`/`terraform apply` from
  fighting ALZ governance (which would either be reverted by policy or, for local_auth, silently
  drift back). Item 4 is a cosmetic provider-representation quirk (declare-or-ignore).
- **The CAE does NOT need to be recreated.** The workload_profile diff is a read-only representation
  artifact of a Consumption-only internal CAE; `terraform apply` cannot remove the implicit
  Consumption profile and would no-op/err rather than recreate. Recreating the CAE would change its
  defaultDomain + static IP (10.0.13.193) → break the WAF FQDN, hub DNS wildcard A record, and Entra
  redirect URIs. Explicitly OUT OF SCOPE / not required.
- Remediation dispatched as infra work item `work/todo/r2b-drift-remediation.md` (config-only;
  acceptance = `terraform plan` shows 0 changes for these items, no security regression). Per
  protocol the orchestrator does not edit child .tf directly.
- OPEN (separate, tracked in plan.md Sprint 4b incident): the NSG `deny-internet-inbound` rule the
  owner manually deleted for VPN reach is still in TF and will re-add on next apply — durable fix is
  an explicit allow for the VPN client range at priority <100 (folded into the same work item).

## r2b DRIFT REMEDIATION — DONE & VERIFIED (2026-07-09) ✅
- Owner confirmed no deletion needed (choice=none_codify); proceeded with config-only fixes.
- Infra specialist implemented all 4 TF edits; critic PASS (all 5 tiers). Commits: 6d2464d (fix),
  ef86eee (critic PASS move-to-done). Item in word-game-infra/work/done/r2b-drift-remediation.md.
- ORCHESTRATOR INDEPENDENT VERIFY: `terraform fmt -check` OK, `terraform validate` Success,
  `terraform plan` (refresh vs live) = **"No changes. Your infrastructure matches the configuration."**
  → the 7 drift lines are GONE, 0 add / 0 change / 0 destroy, NO resource replaced. Confirms the
  fixes are pure config→live alignment (no-op on live) and future provisions won't un-harden.
- Pre-deploy gate PASSED: infra v0.4.2, harness v0.1.4 committed+pushed+tagged (waf v0.2.0,
  web v0.1.1, api v0.1.1, agent v0.1.0 unchanged).
- NO DEPLOY EXECUTED — plan shows 0 changes and no service image changed, so there is nothing for
  azd/terraform apply to push. Release value = drift codified away.
- child-agent-runner MCP transport DEAD (Transport closed) — dispatched via the framework's own
  _start_child_agent_job worker (job 20260709T152122-6a5dcaa981); heartbeat/logs under
  .metrics/child-agent-runner/. repo-index + usage MCP servers were healthy.
