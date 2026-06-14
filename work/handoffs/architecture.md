# Sprint Architecture Handoff

## Scope Summary
Target system: Azure-hosted multiplayer distributed word game with Entra External ID authentication, one globally active game at a time, Foundry-powered category generation, live game orchestration, and CI/CD pipelines.

## System Context
- **Client**: Browser SPA for all user interactions.
- **Control plane**: Game API orchestrating users, locks, rounds, scoring, and projections.
- **Intelligence plane**: Category Agent that generates game categories from configured web sources.
- **Data plane**: Cosmos DB (primary), Blob (optional artifacts), Key Vault (secrets/config), Log Analytics/App Insights.
- **Platform plane**: Azure Container Apps + ACR + private networking + WAF ingress.

## Service Boundaries

### 1) Web SPA (`apps/web`)
Responsibilities:
- Public landing and Entra External ID sign-in/sign-up handoff.
- Name selection with conflict feedback before dashboard access.
- Dashboard views: active users, all-time top 10, today top 3, total games, last winners.
- Game flow UI states:
  - waiting / "Game in progress. Please wait."
  - gathering categories
  - category overview
  - round role screen + countdown
  - guess/score/winner summary
- Category source configuration UI.

NFR constraints:
- MSAL PKCE, token cache in `sessionStorage`.
- No auth tokens in `localStorage`.
- Accessibility + responsive layout.

### 2) Game API (`apps/api`)
Responsibilities:
- JWT verification (`iss`, `aud`, `exp`, `nbf`, `scp`) on all protected endpoints.
- Profile creation and unique display-name reservation.
- Presence tracking and active user roster.
- **Global active game lock** (single game invariant across whole system).
- Game lifecycle orchestration:
  - pre-game
  - gathering categories
  - rounds (2-minute timer)
  - end-game + projection updates
- Leaderboard projections (all-time + daily).
- Real-time fanout interface for game state updates (SSE/WebSocket).

NFR constraints:
- Structured JSON logs + correlation IDs.
- Input validation/rate limiting/security headers.
- Restart-safe persistence semantics.

### 3) Category Agent (`services/category-agent`)
Responsibilities:
- Read configured source URLs.
- Parallel fetch/extract domain-specific terms and 2–3 word phrases.
- Filter generic/stop words; retain category-specific outputs.
- Return one or more categories, with enough entries to support one category per player.
- Write category generation job and output artifacts for audit/replay.

NFR constraints:
- Graceful degradation (agent failures should not crash core API).
- Retry with backoff for transient network/API failures.

### 4) Shared Contracts (`packages/contracts`)
Responsibilities:
- Canonical TypeScript schemas for REST DTOs and event payloads.
- Validation schemas to keep web/api/agent aligned.
- Versioning policy for backward-compatible evolution.

### 5) Infrastructure (`infra`)
Responsibilities:
- Container Apps environment, app identities, ACR pull wiring.
- Cosmos DB, Key Vault, Storage, monitoring stack.
- VNet/subnets/private endpoints/private DNS.
- WAF ingress and NSG boundaries.
- OIDC-based GitHub Actions access.

## Cross-Cutting Invariants
1. Exactly one active game globally (`global-active-game` lock document with CAS semantics).
2. Name uniqueness among active users enforced server-side.
3. Users joining mid-game are gated to wait-state until next game.
4. Score updates are durable and idempotent.
5. Leaderboard projections update at game close and are query-efficient for dashboard reads.
6. Correlation ID travels across web request -> API -> agent -> data operations.

## Recommended Runtime Topology
- `web` Container App: external ingress
- `api` Container App: internal ingress
- `category-agent` Container App: internal ingress
- API invokes agent over private network/authenticated service identity
- Cosmos/Key Vault/Storage via private endpoints
- WAF reverse proxy as designated ingress front door
