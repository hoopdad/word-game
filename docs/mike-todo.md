# Mike TODO (Open unknowns / vagueness to resolve)

1. Define the exact join cutoff: when does “before a game starts” end (button click, category generation start, or round start)?
2. Define rejoin/reconnect handling for users who disconnect mid-game.
3. Define “active user” (heartbeat window, session timeout, duplicate tab handling).
4. Confirm whether the fallback polling limits in `docs/requirements.md` (2s to 30s adaptive backoff, 15-minute cap) need environment-specific overrides.
5. Define canonical timezone for “top 3 of today” leaderboard boundaries.
6. Define the authoritative game-history scope for “all games ever played” (environment-local vs global).
7. Clarify who can edit category-source configuration and required auth/authorization model.
8. Clarify the expected output format from the category agent (schema, confidence thresholds, dedupe rules).
9. Clarify moderation/safety constraints for internet-derived category terms.
10. Clarify correctness arbitration (“any clue-giver judges correct”) and anti-abuse controls.
11. Clarify whether round timer resets after each solved word or is strictly fixed for the full round window.
12. Clarify expected WAF baseline details (required CRS version, rule/paranoia level, and exception handling process).
13. Confirm if any Azure resource besides the dedicated WAF environment may require an explicitly approved public-network exception.
14. Clarify exact list of “child repos” required by setup scripts.
15. Clarify the intended output path/owner for the requested `improvements.md` artifact.
