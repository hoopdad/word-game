# Word Game — Canonical Build Prompt

> **Purpose.** This is the single, canonical prompt for building and deploying the *Word Game*
> system from scratch in one session. It is written as a set of **functional requirements** and
> **manager-level technical requirements** — *what* to build and the *constraints* it must satisfy —
> not a low-level design. The specialist agents for each repo own the detailed design (APIs, file
> layout, libraries, schemas): infer the interfaces from the flows below and build them to meet the
> requirements.
>
> It is reconstructed from the original baseline (`init-pattern.yml`) and reconciled against how the
> system actually ended up working ("how it ended up is how we want it"). Provenance is preserved for
> traceability:
> - **Part 1 — Build Prompt** (the main artifact; build this).
> - **Part 2 — Surviving Requirements** (exact quoted source language + citations).
> - **Part 3 — Changes Since `init-pattern.yml`** (additions, contradictions, winning intent, trail).
> - **Part 4 — INPUTS_REQUIRED** (external dependencies/config for unattended execution).

---

## Assumptions (already provisioned by the runtime — do not block on these)

- `az login` and `gh auth` are complete, with rights to create resources and Entra app
  registrations in the target tenant, and to create repos in the `hoopdad` org.
- Build/runtime toolchain is installed (Azure CLI, `azd`, Terraform, `gh`, `git`, Docker, Python,
  Node, and the language/lint/test tools each stack needs).
- A platform **hub network** exists for Private DNS linkage.
- Outbound network access is permitted to the identity provider, the configured category websites,
  the container registry, and the AI model endpoint.

---

# Part 1 — Build Prompt (MAIN ARTIFACT)

## 1.1 Mission / Outcome

Build and deploy **a multiplayer, distributed game where one player guesses a word based on clues
from the other players.** Anyone loading the website before a game starts can participate. **Only one
game is active at a time in the entire system.**

Success means the application is **fully deployed in Azure, functional end-to-end, reachable by the
public through a single hardened entry point, and users can sign up and log in with Entra External
ID.** All requirements and user flows below must be met.

This is an `azure-fullstack` solution: a web front end, a REST/real-time API, an AI agent, cloud
infrastructure as code, and a web application firewall — delivered as a small fleet of repositories
coordinated by an orchestration harness.

## 1.2 Repositories

Create these private repositories under owner `hoopdad`. Each is owned by a specialist agent that
designs and builds the details for its domain.

| Repo | Role | Responsibility |
|------|------|----------------|
| `word-game-harness` | orchestrator | Coordinates the fleet, owns the cross-service contracts and guardrails, and drives deployment. |
| `word-game-web` | frontend | The player-facing single-page web app. |
| `word-game-api` | backend | Game logic, data access, and real-time messaging. |
| `word-game-agent` | AI agent | Generates word categories from web content using an AI model. |
| `word-game-infra` | infrastructure | All Azure resources as code. |
| `word-game-waf` | WAF / ingress | The single public entry point that filters and routes traffic. |

## 1.3 User Experience & Game Flow (functional requirements)

Build the experience so that:

**Joining and identity**
- Anyone loading the site before a game starts can participate; only one game runs at a time across
  the whole system.
- A user who joins **after** a game has begun sees **"Game in progress. Please wait."** and their
  screen waits until they are eligible to play.
- On first arrival a user must choose a display name before seeing the dashboard. Names must be
  unique and reasonably constrained (a short alphanumeric name). If the name is already taken, tell
  the user **"that name is taken"** and require another; once unique, show the dashboard. Distinguish
  a name that is *badly formatted* from one that is *already taken*, and message each clearly.
- A user can change their display name later from a profile screen, under the same rules.
- The dashboard shows the names of all currently active users and keeps that list current as people
  come and go.

**Dashboard**
- Show the total count of all games ever played.
- Show the **top 10 all-time** scorers and the **top 3 scorers today**.
- Provide a **Start game** button, a **Configure categories** link, and access to the profile screen.
- After a game, return the dashboard to its pre-game state and celebrate the previous winner(s) in a
  status bar.
- Starting a game includes **all** connected users; when a game begins, every connected client moves
  into the game together.

**Categories (AI agent)**
- When a game starts, show a **"gathering categories"** state while the agent works.
- The category agent is an **internet-capable Azure AI Foundry agent**. It reads a configurable list
  of websites (editable from the dashboard's "configure categories" link), visits them **in
  parallel**, and derives **one or more categories** of domain-specific words or **2–3 word phrases**
  from each. It must exclude generic words (articles, prepositions, etc.) as standalone entries,
  though they may appear inside a phrase. There is **one category per player**.
- Category generation must be resilient: bound its runtime and fall back to sensible defaults if it
  is slow or fails, and never let saving the category configuration block the user.

**Rounds, roles, and scoring**
- Begin with an overview of the categories to be used (one per player); a control on that view starts
  the first round.
- At the start of every round, assign roles **randomly**: exactly one **guesser**, everyone else
  **clue-givers**. Show each player their role, then a shared **10-second countdown**.
- A round lasts **2 minutes** and contains one or more guesses. Clue-givers see the secret word; the
  guesser does not (this must be enforced server-side — the guesser must never receive the word).
- When the guesser is correct, as judged by any clue-giver, award **10 points** and show the
  **solved word** to the guesser for **3 seconds**. During that transition the clue-givers are shown
  the **next secret word** while the guesser sees no word; the guesser must never receive the next
  secret word (enforce this server-side). If the 2 minutes expire before a correct guess, award 0
  points and end the round.
- At each round's end, save the score, then randomly pick a player who has not yet been the guesser.
  When everyone has been the guesser, the game ends.
- At game end, show the winner(s) — the player(s) with the most points that game — and update the
  all-time and today's high scores if they were beaten.
- Handle players leaving mid-game gracefully (reconnect window, skip/forfeit a disconnected guesser,
  and keep the game coherent for everyone else).

**Real-time behavior**
- Game play is live: role assignment, countdowns, the current word, guesses, judgments, score
  changes, round transitions, and game-over should reach players promptly without manual refresh.
- A returning or reloading player should be able to rejoin the current game in the correct state.

## 1.4 Technical Requirements (manager-level)

**Platform & deployment**
- Deploy all infrastructure to the **Azure Central US** region.
- Run the services on **Azure Container Apps**, with container images in a private **Azure Container
  Registry**.
- **Deploy with `azd`, run locally from the harness.** A single deployment flow provisions
  infrastructure and then rolls out the services. There is **no** GitHub Actions CI/CD; Azure
  authentication uses the operator's local login. Deploy in the required order: **infrastructure →
  API → agent → web → WAF.**
- Version every service and the web app with **semantic versioning starting at `0.1.0`**, expose a
  version/build endpoint on each service, and **display the version on the web page next to the
  application name**.

**Infrastructure as code**
- All Azure resources are defined as code with **Terraform**.
- **Prefer Azure Verified Modules whenever one exists**; where a native resource is unavoidable,
  record the exception and the reason.
- Provision the data store, registry, secrets store, identity, logging/monitoring, the container
  platform, and the AI model deployment as code. Choose model SKUs/options that are actually
  supported in Central US.

**Networking & the WAF (single public ingress)**
- Use **private networking**: a standalone virtual network with appropriately sized subnets and
  **zero-trust NSGs (deny by default)**. Choose a spoke address range that does not collide with the
  existing platform networks (see the configuration guidance in Part 4). **All resources are private
  with no public endpoints — except the single designated ingress.**
- That ingress is an **open-source WAF** (ModSecurity on nginx, or equivalent) configured to the
  **OWASP Core Rule Set**, blocking at least the **OWASP Top 10**. The WAF is the only component with a public
  endpoint and must stay always-on. Tune the rule set so legitimate API traffic (e.g. JSON bodies and
  standard REST verbs) and real-time/WebSocket upgrades are not falsely blocked, without weakening
  Top-10 protection. **Rate-limit public-facing routes** at the ingress/API boundary while preserving
  legitimate game and real-time traffic.
- The WAF routes the public surface to the right backend: the web UI, the API (including its
  real-time channel), and the agent where applicable. Backends are reachable only from within the
  environment.
- Use private endpoints and **private DNS** for the private resources. **All private DNS zones belong
  in the hub and are linked to every VNet; do not create private DNS zones in the spoke.**
- Terminate TLS at the public ingress and require modern TLS (TLS 1.2+).

**Identity & security**
- Authenticate end users with **Entra External ID (CIAM)** self-service sign-up/sign-in, supporting
  personal and organizational accounts. The web app uses **MSAL** with a PKCE flow and stores tokens
  in session (not local) storage.
- The API validates every request's token (issuer, audience, expiry, not-before, and required scope)
  and rejects missing/expired/invalid tokens with **401**. Identify users by a stable token claim,
  not email.
- Set up Entra app registrations and the sign-up/sign-in user flow **from the workstation via the
  Azure CLI**, not in Terraform. The registered redirect target must match the deployed public app.
- Use **managed identity** for all service-to-service and service-to-Azure access; **no secrets in
  source or in code**. Keep any required secrets in **Key Vault**, accessed via RBAC.
- Authenticate and authorize the real-time channel without exposing bearer tokens in URLs (e.g. via a
  short-lived connection ticket), and authorize every action server-side by the actor's role and game
  state.
- Guard the agent's URL fetching against SSRF (validate scheme/host, bound size and time).
- Render all user-supplied content safely (no injection/XSS), restrict CORS to known origins, and set
  sensible security headers.

**Data**
- Use **Cosmos DB (serverless)** as the primary data store with **Session** consistency and partition
  keys designed for the access patterns. **All persistence — in both dev and production — uses the
  database; do not use in-memory persistence for any activity.** User profiles, category
  configuration, active-user presence, live game state, round history, and scores must all be durable
  and survive restarts and scale events.

**Quality, observability, and operations**
- Each service exposes health and version endpoints, emits structured logs, and runs as a
  non-root, multi-stage container.
- Enforce local quality and security gates before deploying or pushing: language-appropriate linting,
  static application security testing (SAST), Terraform/IaC security scanning, container image
  scanning, unit tests, and a build — appropriate to each stack (Python, TypeScript, Terraform,
  containers). Do not deploy uncommitted or unpushed code.
- Validate the deployment end-to-end, including an authenticated path through the public ingress to
  the API and data store.

## 1.5 Orchestration & Contracts

- The harness coordinates the specialist repos, owns the **shared contracts** between services
  (the web↔API REST surface, the API real-time event surface, and the API↔agent surface), and drives
  the build/deploy flow. **Derive these contracts from the flows in §1.3 and let the specialists
  design the concrete shapes**; keep web, API, and agent aligned to the agreed contracts.
- Keep a short decisions log for non-obvious choices and exceptions (e.g. AVM fallbacks, NFR
  deviations) so future work is traceable.

## 1.6 Acceptance Criteria

- The public ingress serves the app over HTTPS; all backends are private.
- A new user can sign up via Entra External ID, set a unique display name (with clear, correct
  messaging for taken vs. malformed names), and reach the dashboard.
- Two or more users can start exactly one game; roles assign randomly; countdown, 2-minute rounds,
  guesser-only-hidden-word, 10-point scoring with a 3-second reveal, guesser rotation, and end-of-game
  winners all work; leaderboards and the game count update.
- Categories are generated from the configured websites by the AI agent, with a timely fallback, and
  saving the configuration never blocks the user.
- Health and version endpoints respond, the version shows on the web page, OWASP CRS is active
  without breaking legitimate API/real-time traffic, and private networking, managed identity, and
  Key Vault are in force.

---

# Part 2 — Surviving Requirements (exact quoted source language + citations)

> These are preserved **verbatim** (no paraphrasing). Citation format: `<repo-or-file>:<line(s)>`.

**R1 — Core premise.**
> "a multiplayer, distributed game where one player guesses a word based on clues from the other
> players. Anyone loading the website before a game starts can participate. Only one game is active at
> a time in the entire system."
— `init-pattern.yml:21-23` (also `prompts/PROMPT.MD:8`)

**R2 — Late join.**
> "If a user joins after the game begins, the user will see "Game in progress. Please wait." and
> their screen will poll the system until they are eligible to play."
— `prompts/PROMPT.MD:10`

**R3 — Name gate / uniqueness.**
> "When a user first joins they will not see the dashboard. They must set a name. If others in the
> system have chosen the same name, tell them "that name is taken. and they must choose another. Once
> they choose a unique name, they will see the dashboard."
— `prompts/PROMPT.MD:11`

**R4 — Dashboard contents.**
> "The names of all active users are displayed on the main dashboard." /
> "The count of all games ever played is shown on the dashboard." /
> "The top 10 highest scoring players of all time and the top 3 of today are shown on the dashboard."
— `prompts/PROMPT.MD:12-14`

**R5 — Start button.**
> "A button to start a game is shown. If any user clicks that button, the game begins and all users
> are included."
— `prompts/PROMPT.MD:15`

**R6 — Gathering categories.**
> "The game begins with a screen that says "gathering categories". That shows as long as the Category
> agent is working."
— `prompts/PROMPT.MD:16`

**R7 — Category agent (parallel scrape + config table).**
> "The category agent, a Foundry agent with access to the internet, will in parallel connect to all
> the websites lsited in its configuration table. (That configuraiton table is configurable via a
> link on the dashbaord that says "configure categories")."
— `prompts/PROMPT.MD:17`

**R8 — Category extraction rules.**
> "The category agent will read the contents of the web pages and determine 1 or more categories of
> words or 2-3 word phrases specific to that category. … The agent should only include non general
> words; articles, prepositions, etc might be part of a phrase but not a single word. "A" is not valid
> but "A Long Winter's Night" might go with a category "Christmas"."
— `prompts/PROMPT.MD:18`

**R9 — Category overview / one per user.**
> "The game begins with an overview of the categories that will be used. There will be one category
> per user. A button the category view starts the first round."
— `prompts/PROMPT.MD:19`

**R10 — Role assignment + countdown.**
> "At the begining of every round, users are assigned roles randomly. Exactly one user will be named
> as the guesser. The other players will be named as clue-givers. Users are shown their role, then a
> countdown from 10 seconds to 0 is shown to all."
— `prompts/PROMPT.MD:20`

**R11 — Round mechanics & scoring.**
> "The game works in rounds. A round is a group of one or more guesses that occur during a 2 minute
> period. … When the gueser is correct, as judged by any clue-giver, the guesser sees the word on
> their screen for 3 seconds, and gets 10 points for the word. After a correct guess but beffore the 3
> seconds, another word is shown to clue-givers and the guesser's screen shows no word. If time
> expires before the guess is correct, 0 points are awarded and the round will end."
— `prompts/PROMPT.MD:21`

**R12 — Guesser rotation / game end.**
> "At the end of the round, the score is saved to the database. The system will randomly pick a user
> who has not yet been a guesser. If all the users have been guessers in this session, the game ends."
— `prompts/PROMPT.MD:22`

**R13 — Winners & high scores.**
> "At the end of the game, the winner or winners are shown on the screen. The winner is the user with
> the most points during that game. If any of the daily or all-time high scores are beaten, then the
> all time and today's top scores should be updated accordingly."
— `prompts/PROMPT.MD:23`

**R14 — Post-game reset.**
> "After the end of the game, the dashboard resets to pre-game mode with the cards and buttons as
> defined earlier. A status bar will celebrate the winner(s) of the last game."
— `prompts/PROMPT.MD:24`

**R15 — Region.**
> "All infrastructure to be deployed in Azure Central US region"
— `prompts/PROMPT.MD:27`

**R16 — Private networking + spoke skill + DNS placement.**
> "Use private networking and the mcaps-spoke-skill (AKA spoke-skill) to scaffold Terraform for
> networking. Do not add private dns zones to the spoke but only to the hub."
— `prompts/PROMPT.MD:28`

**R17 — Entra via AZ CLI.**
> "Use AZ CLI commands to setup the Entra authentication"
— `prompts/PROMPT.MD:29`

**R18 — Auth requirement (login with Entra External ID).**
> "Success means the CI/CD Actions have deployed the entire application, it is functional, and users
> can log in with Entra External ID."
— `prompts/PROMPT.MD:26` *(the "CI/CD Actions" clause is superseded — see Part 3 C1; the "users can
log in with Entra External ID" requirement survives.)*

**R19 — WAF requirement (nginx + OWASP CRS, private env except WAF).**
> "a WAF container, based on nginix with OWASP CRS rules blocking the top 10 at least … The container
> app environment shoudl have private IP addresses only except for the WAF. The WAF can have public-
> and private-IP addresses. This is a requirement so must be met."
— `prompts/sprint1.md:8`

**R20 — Versioning + on-page version.**
> "Begin versioning each service and web app with 0.1.0 in this iteraiton. … Display the version
> number on the web page by the application name. Use semantic versioning…"
— `prompts/sprint1.md:14`

**R21 — Zero-trust standalone VNet.**
> "Public Network access must be disabled for all resources except the container app that runs the
> WAF. Create a VNet and all necessary subnets, with full NSG targeting zero trust network design.
> This will be a standalone VNet."
— `prompts/sprint1.md:12`

**R22 — Prefer AVM.**
> "Use Azure Verified Modules whenever possible going forward, for a more secure and well-architected
> application."
— `prompts/sprint1.md:10` (reinforced `prompts/next.md:9`: "make sure the agent … always prefers AVM")

**R23 — Single public ingress is the WAF.**
> "Our rules make everything private. There is one exception in the requirements to let an ingress be
> public. The WAF is our ingress and so requires a public endpoint."
— `prompts/sprint2.md:9`

**R24 — Agent stack (Microsoft Agent Framework + Foundry client).**
> "Python AI agent service using Microsoft Agent Framework that uses a Foundry Client for analytical
> or decision-making functions."
— `.repo-index.yml:28` / `.copilot/guardrails/pattern.yml:30-31`

---

# Part 3 — Changes Since `init-pattern.yml`

Baseline file: **`init-pattern.yml`** (project `word-game`, pattern `azure-fullstack`,
`github_owner: hoopdad`, `app_description` = the core premise). The baseline contained **only** the
app premise and pattern selection; everything below was added or changed afterward. Conflicts are
resolved **last-one-wins** (primary: commit timestamp; tiebreaker: session/decision timestamp);
**final implemented behavior wins** where docs disagree.

## 3.1 Additions (new requirements introduced after baseline)

| # | Addition | Source / citation |
|---|----------|-------------------|
| A1 | Full game-flow spec (R2–R14) — late-join, name gate, dashboard cards, rounds, scoring, rotation, winners, reset. | `prompts/PROMPT.MD:10-24` |
| A2 | Entra External ID (CIAM) login; MSAL SPA; server-side JWT validation; scope `access_as_user`. | `nfr.yml:9-16`, `prompts/PROMPT.MD:26,29` |
| A3 | Open-source WAF (nginx + ModSecurity + OWASP CRS) as the sole public ingress. | `prompts/sprint1.md:8`, `prompts/sprint2.md:9`, `word-game-waf/Dockerfile:1` |
| A4 | Zero-trust standalone VNet, NSGs deny-by-default, private endpoints + Private DNS, public access disabled except WAF. | `prompts/sprint1.md:12`, `nfr.yml:23-30`, `word-game-infra/networking.tf` |
| A5 | Prefer Azure Verified Modules; log native fallbacks as exceptions. | `prompts/sprint1.md:10`, `prompts/next.md:9`, `pattern.yml:36` |
| A6 | Semantic versioning from `0.1.0`; `/version` on each service; **version shown on web page**. | `prompts/sprint1.md:14` |
| A7 | Azure AI Foundry account/project + `gpt-4.1-mini` model deployment provisioned in Terraform. | `pattern.yml:35`, `word-game-infra/ai-foundry.tf` |
| A8 | Ticket-based WebSocket auth; flat server event messages; server-side role/state authorization. | `.decisions/log.md:6,14`, `.contracts/websocket-api.yml:8-51` |
| A9 | Cosmos persistence for `users` and `category_config`; async (non-blocking) category-config save. | `.decisions/log.md:35-36` |
| A10 | Profile page (change display name post-registration). | `.decisions/log.md:37` |
| A11 | Presence via 600s inactivity TTL + 30s sweep + 30s dashboard poll. | `.decisions/log.md:44` |
| A12 | 422-format vs 409-taken distinction for display names. | `.decisions/log.md:48-49` |
| A13 | SSRF protections on agent URL fetching (scheme/IP allowlist, DNS validation, size/timeout). | `.decisions/log.md:11`, `word-game-agent/src/content/url_validator.py` |
| A14 | Single-game enforcement + idempotent guess judgment (Cosmos singleton + ETag in durable design). | `.decisions/log.md:8-9` |
| A15 | 30s hard timeout + default-category fallback for category generation. | `.decisions/log.md:10` |
| A16 | Local-azd deployment harness, `.contracts/*`, `.copilot/topology.md`, `.decisions/log.md`, scripts, MCP tools, per-repo skills/agents. | `word-game-harness/*`, `prompts/next.md:3-6`, `prompts/sprint2.md` |
| A17 | Entra setup performed from the workstation via `az` (`scripts/setup-entra.sh`); Entra removed from Terraform. | `prompts/next.md:17`, `.decisions/log.md:17` |

## 3.2 Contradictions (and the winning replacement text)

**C1 — CI/CD mechanism: GitHub Actions → local `azd`.**
- Earlier: *"Build GitHub Actions for CI and CD functions for web, api, Foundry agent, and
  infrastructure. Infrastructure must deploy successfully before the others."* — `prompts/PROMPT.MD:26`
  (reinforced by `prompts/next.md` DevOps section + SHA-named GHA pattern).
- **Winning replacement (final):** *"Migrated from GitHub Actions CI/CD to local azd deployment model
  — single `azd up` from harness deploys all"* and *"Removed OIDC federation and GHA workflows from
  all repos; Azure auth via local az login."*
- Citation trail: `.decisions/log.md:28-30` (2026-06-18) ▸ `nfr.yml:87-95` ▸ `azure.yaml:7-16` ▸
  implementation: **no `.github/workflows/*` in any child repo** (explore of all repos) ▸ commit
  `5addf3b refactor: remove GitHub Actions CI/CD in favor of local azd deploy` (word-game-agent),
  `75b94b0` (word-game-infra). **Winner: local azd.** (The "users can log in with Entra External ID"
  success clause of R18 still survives; only the delivery mechanism changed.)

**C2 — MSAL `redirectUri`: hardcoded → runtime `window.location.origin`.**
- Earlier (security guidance): *"redirectUri: "https://<production-url>", // SECURITY: always hardcode,
  never use window.location.origin"* — `external-user-pattern.md:176,186-188`.
- **Winning replacement (final):** *"MSAL redirectUri: Must use `window.location.origin` at runtime,
  NOT `VITE_*` env var"* — `.copilot/topology.md:145`; implemented as
  `redirectUri: `${window.location.origin}/welcome`` — `word-game-web/src/main.tsx`. **Winner:
  runtime derivation** (resolves multi-FQDN/WAF fronting; later timestamp + implementation).

**C3 — Redirect path: `/auth/callback` → `/welcome`.**
- Earlier: `scripts/setup-entra.sh` builds redirect URIs ending in `/auth/callback`
  (`setup-entra.sh:182,193`).
- **Winning replacement (final):** the web app and deploy script use **`/welcome`**
  (`azd-deploy.sh:190`, `word-game-web/src/main.tsx`). **Winner: `/welcome`.** *(INPUTS_REQUIRED: the
  SPA redirect URI registered in Entra must match `https://<waf-fqdn>/welcome`.)*

**C4 — Container Apps ownership: defined in infra → split out of infra.**
- Earlier: pattern/topology imply infra defines the container apps
  (`.copilot/topology.md:112-123` lists `containerapps.tf`).
- **Winning replacement (final):** *"Container App resources split from word-game-infra … Container
  App Environments remain in infra TF (platform resource); individual apps are ephemeral per-deploy."*
  — `.decisions/log.md:18-19`; `prompts/next.md:11`. Terraform defines **only the two CAEs**; apps are
  created by `scripts/azd-deploy.sh`. **Winner: split out.**

**C5 — Container App naming: SHA-named ephemeral apps → in-place fixed-name apps.**
- Earlier: *"create a new container app with a consistent root name and use the SHA to create a unique
  name … destroy the existing … wordgame-{service}-v{sha7}"* — `prompts/next.md` DevOps §2,
  `.decisions/log.md:20`.
- **Winning replacement (final):** `azd-deploy.sh` updates fixed-name apps (`word-game-{service}`)
  in place and tags the **image** with the short SHA (`:sha` + `:latest`). **Winner: in-place
  fixed-name apps, SHA-tagged images** (`azd-deploy.sh:55-143`).

**C6 — Network mode: internal-only CAE → external "edge" CAE with internal backend apps.**
- Earlier (NFR): *"Container Apps Environment must be VNet-integrated (internal mode)"* — `nfr.yml:26`.
- **Winning replacement (final):** *"Moved all services to external edge CAE (salmonpond) —
  internal-only CAE blocked public WAF access. Backend apps use internal ingress (same-env only)
  within the external environment. NFR deviation: CAE is external (not internal mode) but backend apps
  remain unexposed."* — `.decisions/log.md:34`. Terraform provisions **both** an internal and an edge
  CAE; services deploy to edge with web/api/agent on **internal** ingress and WAF **external**.
  **Winner: external edge CAE + internal backend ingress** (documented NFR deviation).

**C7 — Agent LLM client: Azure AI Inference SDK → `FoundryChatClient`.**
- Mid-history flip-flop: *"word-game-agent FoundryClient rewritten to use real Azure AI Inference SDK
  with managed identity"* — `.decisions/log.md:31` (2026-06-18).
- **Winning replacement (final, later same day + implementation):** *"category extraction uses
  agent_framework.foundry.FoundryChatClient with managed identity; agent-framework 1.8.1 exposes the
  required client so azure-ai-inference fallback is unnecessary"* — `.decisions/log.md:26`;
  implemented in `word-game-agent/src/agent/foundry_client.py`. **Winner: `FoundryChatClient` +
  managed identity.**

**C8 — Foundry model deployment SKU: `Standard` → `GlobalStandard`.**
- Earlier: `Standard` SKU attempted. Terraform apply failed: *"The specified SKU 'Standard' for model
  'gpt-4.1-mini 2025-04-14' is not supported in this region 'centralus'."* — `word-game-harness/
  tf-err.txt`.
- **Winning replacement (final):** *"GPT-4.1-mini deployed with GlobalStandard SKU in Central US
  (Standard SKU not supported in this region)."* — `.decisions/log.md:16`. **Winner: GlobalStandard.**

**C9 — Cosmos data-plane access: ARM RBAC → Cosmos SQL role assignment.**
- **Winning replacement (final):** *"Cosmos data-plane access uses cosmosdb_sql_role_assignment (not
  ARM RBAC) with built-in Data Contributor role."* — `.decisions/log.md:25`;
  `word-game-infra/identity.tf`. **Winner: `cosmosdb_sql_role_assignment`.**

**C10 — Private DNS placement: spoke deviation → hub-only (per explicit direction).**
- Requirement R16: *"Do not add private dns zones to the spoke but only to the hub."* —
  `prompts/PROMPT.MD:28`.
- The earlier implementation deviated (Cosmos/CAE zones placed in the spoke because the private
  endpoints could not otherwise resolve — `.decisions/log.md:40`).
- **Winning rule (per current direction):** **all private DNS zones belong in the hub and are linked
  to every VNet; none are created in the spoke.** The spoke deviation is superseded — re-home the
  Cosmos and Container Apps private DNS zones to the hub and link them to the spoke VNet. **Winner:
  hub-only.**

**C11 — Scale-to-zero vs min-replicas.**
- NFR cost rule: *"Enable scale-to-zero on all Container Apps (min replicas: 0 for non-prod)"* —
  `nfr.yml:67`.
- **Winning replacement (final):** api/agent keep min 0; **web and WAF pin `min-replicas=1`** (web
  cold-start activation failure; WAF is the public entry point) — `azd-deploy.sh:217-243,282`,
  `.decisions/log.md` (2026-06-19 web min-replicas fix). **Winner: web/WAF min 1.**

## 3.3 Gaps detected in the final implementation (carry into Part 1 to make the canonical build complete)

| Gap | Evidence | Resolution in canonical prompt |
|-----|----------|--------------------------------|
| G1 — On-page **version display** (R20/A6) not implemented in the SPA. | explore of `word-game-web` (no version near app name; `LandingPage.tsx`). | Part 1 §1.6 web requires it; `/version` exists in all services. |
| G2 — **Games/rounds/scores persisted only in-memory** (API), despite the requirement to save scores to the database (R12) and decision A9. | `word-game-api/app/services/store.py` (ScoreStore/games in-memory). | Canonical build requires **all** state (profiles, presence, live game, rounds, scores, category config) to persist to the database in **both dev and production** — no in-memory persistence for any activity. |
| G3 — Agent `requirements.txt` **unpinned**. | `word-game-agent/requirements.txt`. | Pin versions (esp. `agent-framework>=1.8.1`) in canonical build. |
| G4 — Agent specialist docs reference `app/` while code is under `src/`. | `word-game-agent/.github/agents/*`. | Canonical layout uses `src/`. |

---


# Part 4 — INPUTS_REQUIRED

**Gather, do not hard-code.** Assume the Azure CLI is already logged in to the **correct tenant and
subscription**. Agents must *infer or gather* configuration at build/deploy time rather than treating
it as manual input, using these sources in priority order:

1. **Terraform outputs** — everything the infrastructure creates is read from `terraform output`
   (resource group, VNet/subnets, Container Apps environment(s), Cosmos endpoint + database, Key
   Vault URI, Container Registry login server, user-assigned managed identity, AI model endpoint +
   deployment name, and the application's own Log Analytics workspace). These are **never** manual
   inputs; the harness wires them into the services at deploy time. (A central/hub Log Analytics
   workspace, if diagnostics are forwarded there, is pre-existing and located via `az` — see source 3.)
2. **`../mikeo-lab/cidr.txt`** (platform CIDR inventory) — use it to (a) identify the **hub** VNet by
   name, its resource group, region, and address space, and (b) choose a **non-overlapping spoke** VNet
   and subnet range for this project, avoiding every range listed there and the documented collisions.
   The hub may live in a different subscription: search the accessible subscriptions (`az account
   list`) for the hub VNet/RG named in `cidr.txt` to locate it.
3. **`az` CLI queries** — anything not covered above: current subscription/tenant (`az account
   show`), the hub subscription that owns the hub VNet and its central Log Analytics workspace,
   region-supported model SKUs, the Entra app IDs, and the deployed public ingress FQDN (read back
   after they are created), etc.

**Created during the run — not inputs:** Entra app registrations (web + API client IDs), the API
scope, the sign-up/sign-in user flow, and the redirect target are **created by the Azure-CLI Entra
setup step** and then read back via `az`. Cosmos/Key Vault/Registry/identity/model resources are
**created by Terraform** and read from its outputs. Do not list any of these as inputs, and do not
hard-code their values.

**The only genuine external inputs (confirm defaults; everything else is gathered):**

| Input | Default | Notes |
|-------|---------|-------|
| GitHub owner / visibility | `hoopdad` / **private** | From the baseline `init-pattern.yml`. |
| Project name / resource prefix | `word-game` | From the baseline; drives resource and repo naming. Per-environment names (e.g. a `wordgame-dev` resource prefix) are **derived** from this, not supplied separately. |
| Azure region | **`centralus`** | Binding (R15); the hub also lives here per `cidr.txt`. |
| Category seed website(s) | `https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-highlyavailable` | The only true data input; seed the database with this exact URL on first run (the R8 example). **Editable in-app** via "configure categories". |

**Operational note (not an input):** the real-time channel is single-replica by default; scaling the
API to multiple replicas requires a shared broadcast backplane (e.g. Redis or Azure Web PubSub).
Decide per environment and record the choice in the decisions log.
