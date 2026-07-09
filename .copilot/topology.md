# word-game — Project Topology & Quick Reference

Use this file to eliminate repeated file discovery (find/grep) in sessions.
Agents should consult this FIRST before searching for files.

> Values marked `<set-after-provision>` are filled in by the orchestrator after the first
> `azd provision` / `azd up` (read them from `.azure/tf-outputs.json`).

## Deployment Model

- **Method**: Local `azd up` from word-game-harness (NOT GitHub Actions)
- **Infra**: Terraform with local state (`.azure/tf-outputs.json` has all outputs)
- **Images**: `az acr build` to the project ACR (not docker push)
- **Deploy script**: `scripts/azd-deploy.sh` (builds + deploys all services)
- **Verify**: `scripts/verify-deploy.sh` (post-deploy smoke test)
- **Pre-deploy gate**: `scripts/predeploy-gate.sh` (commit + push + version-tag every repo)

## Azure Resource IDs

| Resource | Name | Resource Group |
|----------|------|----------------|
| ACR | <set-after-provision> | rg-word-game-dev |
| Container App Env | <set-after-provision> | rg-word-game-dev |
| WAF App | word-game-waf | rg-word-game-dev |
| Web App | word-game-web | rg-word-game-dev |
| API App | word-game-api | rg-word-game-dev |
| Agent App | word-game-agent | rg-word-game-dev |
| Cosmos DB | <set-after-provision> | rg-word-game-dev |
| Key Vault | <set-after-provision> | rg-word-game-dev |

- Region: centralus

## Entra ID Configuration

| App | Client ID | Purpose |
|-----|-----------|---------|
| Web (SPA) | <set-after-provision> | MSAL browser auth |
| API | <set-after-provision> | Token validation |
| Tenant | <set-after-provision> | Directory |

- API Scope: `api://<api-client-id>/access_as_user`
- Redirect URIs (SPA platform): production WAF FQDN + `/welcome`

## Request Flow (User → WAF → Services)

```
User Browser
  │
  ├── GET /* (SPA routes)  →  WAF (:443) → word-game-web (:80)
  ├── GET/POST /api/*      →  WAF (:443) → word-game-api (:8000)
  ├── WS /ws/*             →  WAF (:443) → word-game-api (:8000)
  └── POST /agent/*        →  WAF (:443) → word-game-agent (:8000)
```

WAF FQDN: `<set-after-provision>`

## Key File Locations

### word-game-harness
| Purpose | Path |
|---------|------|
| Azure config | azure.yaml |
| Terraform outputs | .azure/tf-outputs.json |
| Deploy all services | scripts/azd-deploy.sh |
| Pre-deploy gate (commit/push/tag) | scripts/predeploy-gate.sh |
| Post-deploy verify | scripts/verify-deploy.sh |
| Guardrails | .copilot/guardrails/pattern.yml, nfr.yml |
| Contracts | .contracts/ |

### word-game-web
| Purpose | Path |
|---------|------|
| MSAL auth hook | src/hooks/useAuth.ts |
| App entry (MSAL config) | src/App.tsx |
| API client | src/services/apiClient.ts |
| Dockerfile | Dockerfile |
| Nginx config | nginx.conf |

### word-game-api
| Purpose | Path |
|---------|------|
| FastAPI main | app/main.py |
| Pydantic models | app/models.py |
| Auth/JWT validation | app/auth.py |
| Route handlers | app/routes/ |
| Dockerfile | Dockerfile |

### word-game-waf
| Purpose | Path |
|---------|------|
| Nginx config template | docker/nginx/nginx.conf.template |
| ModSecurity overrides | docker/modsecurity/modsecurity-override.conf |
| Dockerfile | Dockerfile |

### word-game-agent
| Purpose | Path |
|---------|------|
| Agent main | app/main.py |
| Foundry client | app/foundry_client.py |
| Dockerfile | Dockerfile |

### word-game-infra
| Purpose | Path |
|---------|------|
| Main config | main.tf |
| Container Apps | containerapps.tf |
| Networking/VNet | networking.tf |
| ACR | acr.tf |
| Cosmos DB | cosmos.tf |
| Key Vault | keyvault.tf |
| Variables / Outputs | variables.tf / outputs.tf |

## Deployment Wait Pattern (NO sleep!)

Instead of `sleep N && az containerapp revision show ...`, poll with a timeout:

```bash
TIMEOUT=120; ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  STATE=$(az containerapp revision show --name $APP --resource-group $RG \
    --revision $REV --query properties.runningState -o tsv 2>/dev/null || echo "Unknown")
  case "$STATE" in
    Running) echo "✅ $APP running"; break ;;
    Failed)  echo "❌ $APP failed"; exit 1 ;;
    *)       sleep 10; ELAPSED=$((ELAPSED + 10)) ;;
  esac
done
```

## Common Mistakes to Avoid

1. **MSAL redirectUri**: Must use `window.location.origin` at runtime, NOT a `VITE_*` env var
2. **Vite build args**: `VITE_*` must be ARG→ENV BEFORE `npm run build` in Dockerfile
3. **Token fallback**: Use `acquireTokenPopup`, NEVER `acquireTokenRedirect` (causes infinite loops)
4. **API field names**: Always snake_case in request bodies (Python/Pydantic convention)
5. **WAF min replicas**: Must be 1 (not 0) — it's the public entry point
6. **OWASP CRS 911100**: Blocks PUT/PATCH/DELETE by default — must exclude for API paths
7. **ACR access**: `public_network_access_enabled=true` needed for `az acr build`
8. **nginx map_hash_bucket_size**: Set to 128 for long ACA FQDNs
9. **Deploy gate**: Commit + push + tag every repo BEFORE `azd up` (use `scripts/predeploy-gate.sh`)

## Child Agent Dispatch Model

Use `phase="full"` for the standard workflow (preferred):

```
start_child_agents_batch(repos=["word-game-api", "word-game-web"], phase="full")
```

This runs a single Copilot session per repo that drains `work/todo/` through an integrated
specialist → critic loop (5-tier review; up to 3 fix cycles per item) and exits when empty.

Available phases:
- `phase="full"` — integrated specialist+critic loop (default for production use)
- `phase="specialist"` — specialist only, moves to `work/ready-for-review/`
- `phase="critic"` — critic only, picks from `work/ready-for-review/`

## Service Deploy Contract (Sprint 4 — filled from infra outputs + code)

Terraform (../word-game-infra) provisions the **platform only** (RG `rg-word-game-dev`, CAE
`cae-word-game-dev` [internal LB], ACR, Cosmos `wordgame` [private endpoint], Foundry + GPT-4.1-mini,
UAMI with AcrPull/KeyVault/Cosmos-data roles). The **four Container Apps are created by
`scripts/azd-deploy.sh`** (build via `az acr build`, deploy via `az containerapp`), in dependency
order agent → api → web → waf. All apps run with the UAMI (`AZURE_CLIENT_ID=<uami_client_id>`).

| App | Image | Ingress | Port | Key env / build args |
|-----|-------|---------|------|----------------------|
| word-game-agent | word-game-agent | internal | 8000 | `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_MODEL`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_REGION` |
| word-game-api | word-game-api | internal | 8000 | `WORD_GAME_*` prefix: `COSMOS_ENDPOINT`, `COSMOS_DATABASE`(=`wordgame`), `ENTRA_ISSUER`, `ENTRA_AUDIENCE`(=API client id), `AGENT_ENDPOINT`(=`http://word-game-agent`), `ALLOWED_ORIGINS`; plus `AZURE_CLIENT_ID` |
| word-game-web | word-game-web | internal | 80 | build args `VITE_MSAL_CLIENT_ID`(SPA), `VITE_MSAL_API_CLIENT_ID`(API); redirectUri from `window.location.origin` at runtime |
| word-game-waf | word-game-waf | **external** | 8080 | `BACKEND_WEB=word-game-web:80`, `BACKEND_API=word-game-api:80`, `BACKEND_AGENT=word-game-agent:80`, `PORT=8080` |

- WAF nginx routes: `/health`(local), `/ws/`→api (WS upgrade), `/api/`→api, `/agent/`→agent, `/`→web.
- Intra-CAE calls use app short-names on port 80 with `--allow-insecure` (nginx proxies http upstream).
- Cosmos DB name is **`wordgame`** (api default `word-game` is overridden from the TF output).
- CAE is internal → the WAF FQDN is reachable only on the VNet (VPN required to browse/verify/e2e).
