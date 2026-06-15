# improvements.md

Critic review of `PROMPT.MD`, `nfr.yml`, and `external-user-pattern.md`.

## Clarity gaps
- `PROMPT.MD`: minimum player count is never stated; a game needs at least 2 players, and the UI should say what happens below the threshold.
- `PROMPT.MD`: “as judged by any clue-giver” does not define the UI control or server arbitration rule.
- `PROMPT.MD`: real-time sync protocol is unspecified; choose WebSocket, SSE, or polling explicitly.
- `PROMPT.MD`: category-to-user ratio is undefined when configured categories and player count differ.
- `PROMPT.MD`: category-agent timeout and failure behavior are missing.
- `PROMPT.MD`: “today” leaderboard timezone is undefined; UTC should be the default.
- `PROMPT.MD`: “active users” is undefined.
- `PROMPT.MD`: late-joiner polling interval is missing.
- `PROMPT.MD`: player disconnect behavior during active games is unspecified.
- `PROMPT.MD`: score persistence model is incomplete.
- `PROMPT.MD`: leaderboard tiebreak rules are missing.
- `PROMPT.MD`: single active-game enforcement needs a concrete concurrency mechanism.

## Contradictions
- `nfr.yml` says scale-to-zero is desired, but the game needs persistent real-time connectivity; the game API needs a carve-out.
- `nfr.yml` and `external-user-pattern.md` should agree on how the in-game display name is sourced.
- `nfr.yml` mandates self-hosted runners, but the repo workflows currently use GitHub-hosted runners.

## Security-risk ambiguities
- The “configure categories” link needs admin-only access control and URL allowlisting to prevent SSRF.
- The game must prevent guessers from retrieving the current word through shared APIs or streams.
- Game start should be rate-limited to avoid DoS and runaway agent cost.
- Name uniqueness must be atomic and return `409 Conflict` on race conditions.
- Agent-scraped content needs moderation before it becomes playable vocabulary.
- Token expiry during gameplay needs silent renewal behavior and 401 handling.

## Missing requirements
- Data retention policy for scores, profiles, and round history.
- Explicit deployment environment matrix (`dev`, `prod`, etc.).
- Browser refresh behavior during an active game.
- Maximum URL count for category configuration.
- Behavior when all players disconnect.
- `external-user-pattern.md` should correct the app registration audience guidance for CIAM.
