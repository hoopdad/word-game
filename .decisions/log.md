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
