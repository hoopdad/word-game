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
