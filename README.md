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
  - `infra` (`mcaps-infra/**`)
- `CD` (`cd.yml`) runs on pushes to `main` and supports manual `workflow_dispatch`.
  - Infra deploy runs first (Terraform spoke stack in `mcaps-infra/`, remote azurerm backend).
  - App deployments (`web`, `api`, `agent`, `waf`) depend on successful infra deploy.

### Bootstrap scripts

Run these once in order when setting up a new clone.

| Script | Phase | Purpose |
|---|---|---|
| `scripts/bootstrap-prereqs.sh` | 1 — pre-run | Check tools, sync child repos, `npm install` |
| `scripts/setup-oidc.sh` | 2 — pre-deploy | Create Azure AD app + OIDC federated creds, set GitHub secrets |
| `scripts/setup-github-vars.sh` | 3 — post-deploy | Set GitHub variables for Entra auth config after infra is deployed |
| `scripts/reset-azure-dev.sh --yes` | destructive | Delete `rg-wordgame-dev` so the CI/CD pipeline can recreate it |

Sprint 1a also added phase-specific helpers:

- `scripts/bootstrap-prereqs-pre.sh` — create or reuse the deployment identity and GitHub OIDC secrets before infrastructure deployment
- `scripts/bootstrap-prereqs-post.sh` — capture the deployed WAF hostname and update GitHub variables afterward
- `scripts/destroy-old-infra.sh --yes` — tear down the legacy `rg-wordgame-dev` resource group (also runnable via the gated `Destroy legacy infra` workflow)

```bash
# 1. After cloning
scripts/bootstrap-prereqs.sh

# 2. Log in, then configure OIDC (required before the first CD run)
az login && az account set --subscription <id>
gh auth login
scripts/setup-oidc.sh

# 3. After infra is deployed by CD, set app-config variables
#    Provide the Entra app client IDs; PUBLIC_APP_URL is auto-detected from the deployed WAF.
SPA_CLIENT_ID=<spa-client-id> API_CLIENT_ID=<api-client-id> scripts/setup-github-vars.sh
```

All scripts are idempotent — re-running them is safe.

### Azure OIDC configuration (reference)

Use GitHub OIDC federation (no long-lived Azure client secret in repo or workflow code).
`scripts/setup-oidc.sh` performs this setup automatically.

Required repository secrets (written by `setup-oidc.sh`):

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Optional repository variable:

- `AZURE_LOCATION` (defaults to **Central US**: `centralus` when not set)

### Monitoring runs

- PR CI: `scripts/watch-workflow.sh CI pull_request <feature-branch>`
- Main CD: `scripts/watch-workflow.sh CD push main`
