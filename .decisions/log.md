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
