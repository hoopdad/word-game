# Requirements (Consolidated)

This file is the single source of truth for requirements previously described in `PROMPT.MD`, `sprint1.md`, and `sprint1a.md`.

## 1) Product and game behavior

1. The system is a multiplayer, distributed web game with exactly one active game at a time across the entire system.
2. Users who arrive before a game starts can join that upcoming game; "before start" ends when the start button is clicked.
3. Users who arrive after a game has started must see `Game in progress. Please wait.` and the UI must keep checking eligibility until they can join.
4. Eligibility updates should use event-driven delivery when available (for example, SSE/WebSocket). If polling fallback is required, it must use bounded adaptive backoff (start at 2s, back off up to 30s max, and stop/clean up after 15 minutes or on navigation away).
5. A first-time user must set a unique display name before seeing the dashboard.
6. If a chosen name is already in use, the UI must block progress and show that the name is taken.
7. The dashboard must show:
   - all active user names,
   - count of all games ever played,
   - top 10 all-time high scorers,
   - top 3 scorers for today.
8. Any user can start the game via the dashboard start button; when started, all currently eligible users are included.
9. Rejoin/reconnect is allowed for users who were already included in the started game.
10. "Active user" means a user included in the started game who is currently receiving words in the game UI.

## 2) Category generation and configuration

1. On game start, all users must see a `gathering categories` state while category generation is running.
2. Category generation must be handled by a Foundry agent with internet access.
3. The category agent must fetch all configured source websites in parallel.
4. A dashboard link (`configure categories`) must allow configuration of category-source websites.
5. The category agent must extract category-specific words and 2-3 word phrases from source content.
6. Generic single words (for example, articles/prepositions) must be excluded unless part of a valid phrase.
7. Before the first round, the game must show a category overview and provide a button to start rounds.
8. The game must use one category per participating user.
9. Category-source configuration is editable by all authenticated users.
10. Category agent canonical output schema is an array of category objects: `[{"category":"x","phrases":["key phrase 1","key phrase 2"]}]`.
11. Category terms must be office-appropriate and exclude self-harm content, disparaging/derogatory language, and discriminatory/intimidating content.

## 3) Round, role, and scoring rules

1. At the start of each round, users are randomly assigned roles:
   - exactly one guesser,
   - all others are clue-givers.
2. After role assignment, all users must see a 10-second countdown.
3. A round lasts 2 minutes and can contain one or more guess attempts.
4. Clue-givers see the target word; the guesser does not.
5. A guess is correct when any clue-giver judges it correct.
6. Correctness arbitration is explicit: a clue-giver confirms correctness by clicking `got it`.
7. When `got it` is used, all players must see who agreed, formatted as `<user name> agrees with the answer`.
8. On correct guess:
   - guesser receives 10 points,
   - guesser sees the solved word for 3 seconds,
   - then a new word is shown to clue-givers.
9. "New category" means a new round; there is exactly one timer window per round, and the timer does not pause or reset during that round.
10. If round time expires before a correct guess, 0 points are awarded for that unresolved word and the round ends.
11. At round end, scores must be persisted atomically (or via idempotent upsert semantics) so retries/restarts do not double-write or lose results.
12. Persisted game/round records must be restart-safe: a fresh process must be able to replay the latest committed state and continue correctly after interruption.
13. The next round’s guesser must be randomly selected from users who have not yet been guesser in the current game.
14. The game ends when all participating users have been guesser.

## 4) Game completion and leaderboard updates

1. At game end, winner(s) are the player(s) with highest points for that game and must be shown in the UI.
2. If game results exceed current daily or all-time leaderboard entries, those leaderboard records must be updated.
3. Daily leaderboard boundaries use UTC.
4. "All games ever played" is scoped to all games stored in the current database.
5. After game end, the dashboard must reset to pre-game mode.
6. The reset dashboard must include a status bar celebrating the winner(s) of the last game.

## 5) Security, networking, and infrastructure

1. The deployment target is Azure and must support all required user flows.
2. Public network access must be disabled for all resources except the WAF ingress path.
3. A WAF container (NGINX + OWASP CRS protecting at least OWASP Top 10 classes) is required.
4. WAF baseline must run OWASP CRS at paranoia level PL2.
5. Backend Container Apps environments must remain private/internal. The dedicated WAF Container Apps environment may enable public network access only to host the WAF public edge.
6. A dedicated VNet with required subnets and NSGs must be implemented using zero-trust principles.
7. The Entra External ID sign-up/sign-in flow must be fixed so `AADSTS500113` is remediated (a valid reply URL is registered and functional).
8. Terraform planning must include migration toward Azure Verified Modules, using AVM where possible going forward.
9. The only approved public ingress path is Internet → WAF container app in the dedicated WAF environment; web/api/agent backends must remain private-only.
10. No Azure resource besides the dedicated WAF environment may use an explicitly approved public-network exception.

### 5.1 Red-team/remediation controls (public ingress exception)

1. Red-team check: confirm only the WAF container app has external ingress enabled and only the WAF environment is allowed public network access.
2. Red-team check: confirm backend ingress cannot be reached directly from Internet (NSG + ACA internal environment).
3. Remediation: if any backend is public, disable external ingress immediately and route traffic only through WAF.
4. Remediation verification: rerun Terraform validate and standard CI checks before deployment.
5. WAF violations should return a standardized user-facing error response: HTTP 403 with a stable error code/message and a correlation ID for support/debugging.

## 6) Delivery, versioning, and automation

1. CI/CD workflows must cover web, API, Foundry agent, and infrastructure.
2. Infrastructure deployment must succeed before dependent service/app deployments.
3. The sprint outcome requires a successful CI/CD run with passing tests and a functional deployed application.
4. Each service and web app must start versioning at `0.1.0` in this iteration and follow semantic versioning thereafter.
5. The application version must be displayed in the web UI near the application name.
6. CD must be used to publish version updates.
7. Repository automation scripts must be added for fresh setup, including:
   - cloning/downloading this repo and required child repos (`word-game`, `word-game-api`, `word-game-agent`, `word-game-infra`, `word-game-web`),
   - configuring non-Terraform prerequisites (for example, GitHub OIDC-to-Azure auth setup),
   - separating prerequisite steps from post-deploy steps.
8. Existing scripts in `./scripts` must be preferred over bespoke command sequences when equivalent coverage exists.
9. Requirements updates supersede separate `improvements.md` requests; improvements should be merged into this document.

## 7) Cross-reference requirements

1. Additional requirements from `nfr.yml` and `external-user-pattern.md` must be satisfied.
