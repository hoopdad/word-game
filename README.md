# Word Game Baseline

Minimal full-stack foundation for a multiplayer word game.

## Quick start

```bash
npm install
npm run db:migrate
npm run db:seed
npm run dev
```

- Frontend: http://localhost:5173
- Backend API/WS: http://localhost:3001

## Scripts

- `npm run dev` - run frontend and backend
- `npm run build` - build backend bundle and frontend assets
- `npm run test` - run sanity tests for backend and frontend
- `npm run db:migrate` - apply SQLite migrations
- `npm run db:seed` - seed baseline data

## API auth environment

The API validates Entra External ID access tokens on protected routes.

1. Copy `apps/api/.env.example` to `apps/api/.env`.
2. Fill in issuer, audience, required scope, and JWKS URI values for your tenant.
3. Do not commit real tenant IDs, client IDs, or secrets.

## CI/CD pipelines

GitHub Actions workflows live in `.github/workflows`:

- `CI` (`ci.yml`) runs on pull requests and uses path-filtered jobs for:
  - `web` (`apps/web/**`)
  - `api` (`apps/api/**`)
  - `agent` (`apps/agent/**`)
  - `infra` (`infra/**`)
- `CD` (`cd.yml`) runs on pushes to `main` and supports manual `workflow_dispatch`.
  - Infra deploy runs first.
  - App deployments (`web`, `api`, `agent`) depend on successful infra deploy.

### Azure OIDC configuration

Use GitHub OIDC federation (no long-lived Azure client secret in repo or workflow code).

Required repository secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Optional repository variable:

- `AZURE_LOCATION` (defaults to **Central US**: `centralus` when not set)

### Monitoring runs

- PR CI: `scripts/watch-workflow.sh CI pull_request <feature-branch>`
- Main CD: `scripts/watch-workflow.sh CD push main`
