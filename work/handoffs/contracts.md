# API / Event / Data Contracts Handoff

## Auth + Profile Contracts

### `GET /api/v1/profile`
- `200`: `{ userId, displayName, createdAt }`
- `404`: `{ code: "profile_not_found" }`

### `POST /api/v1/profile`
Request:
```json
{ "displayName": "PlayerOne" }
```
Responses:
- `201`: `{ userId, displayName, createdAt }`
- `409`: `{ code: "name_taken", message: "that name is taken." }`
- `400`: invalid format/length

Rules:
- `sub` claim is stable user identity key.
- Display name uniqueness checked against active-user namespace and persisted user profile constraints.

## Dashboard Contracts

### `GET /api/v1/dashboard`
`200`:
```json
{
  "activeUsers": [{ "userId": "u1", "displayName": "Alpha" }],
  "totalGamesPlayed": 42,
  "topAllTime": [{ "displayName": "A", "score": 250 }],
  "topToday": [{ "displayName": "B", "score": 80 }],
  "lastWinners": ["Alpha", "Beta"],
  "gameState": "idle"
}
```

## Category Source + Generation Contracts

### `GET /api/v1/categories/sources`
- `200`: `{ sources: [{ id, url, enabled, updatedAt }] }`

### `POST /api/v1/categories/sources`
Request:
```json
{ "url": "https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-highlyavailable", "enabled": true }
```
Responses: `201|409|400`

### `POST /api/v1/game/start`
- Side effect: acquire global lock; enqueue category generation job.
- `202`: `{ gameId, status: "gathering_categories" }`
- `409`: `{ code: "game_in_progress" }`

### `GET /api/v1/game/active`
- `200`: full current state snapshot
- `404`: no active game

## Round + Scoring Contracts

### `POST /api/v1/rounds/{roundId}/guess/correct`
Request:
```json
{ "guesserUserId": "u2", "word": "VPN Gateway", "judgedBy": "u5" }
```
Responses:
- `200`: `{ awardedPoints: 10, nextWordAvailable: true }`
- `409`: `{ code: "round_closed" }`

### `POST /api/v1/rounds/{roundId}/expire`
- closes active round when timer reaches 2 minutes without successful completion path.

## Event Contracts (pub/sub or stream)

- `user.joined`
- `user.name_reserved`
- `game.start_requested`
- `game.lock_acquired`
- `categories.generation.started`
- `categories.generation.completed`
- `categories.generation.failed`
- `round.started`
- `round.role_assigned`
- `guess.correct`
- `round.ended`
- `game.ended`
- `leaderboard.updated`

Common event envelope:
```json
{
  "eventId": "uuid",
  "eventType": "round.started",
  "occurredAt": "2026-06-13T23:17:33Z",
  "correlationId": "uuid",
  "gameId": "g1",
  "payload": {}
}
```

## Data Model Contracts (Cosmos)

### `global_locks` container
```json
{
  "id": "global-active-game",
  "gameId": "g1",
  "status": "held",
  "acquiredAt": "...",
  "leaseUntil": "...",
  "_etag": "for-cas"
}
```

### `games` container
```json
{
  "id": "g1",
  "status": "gathering_categories|in_round|finished",
  "players": [{ "userId": "u1", "displayName": "Alpha" }],
  "roundOrder": ["u1", "u2"],
  "currentRound": 2,
  "startedAt": "...",
  "endedAt": null
}
```

### `rounds` container
```json
{
  "id": "g1-r2",
  "gameId": "g1",
  "guesserUserId": "u2",
  "clueGiverUserIds": ["u1", "u3"],
  "startedAt": "...",
  "deadlineAt": "...",
  "awardedPoints": 20,
  "status": "active|expired|closed"
}
```

### `scores` container
- Immutable per-guess records + projection updater materializing:
  - all-time top 10
  - day-bucket top 3

### `category_jobs` and `category_results`
- Track lifecycle and reproducibility of generated categories.

## Validation + Compatibility Rules
- Contracts versioned (`v1`) and validated in shared package.
- Additive changes only within minor versions.
- Breaking schema changes require new version namespace.
