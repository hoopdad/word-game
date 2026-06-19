# Word Game — Project Topology & Quick Reference

Use this file to eliminate repeated file discovery (find/grep) in sessions.
Agents should consult this FIRST before searching for files.

## Deployment Model

- **Method**: Local `azd up` from word-game-harness (NOT GitHub Actions)
- **Infra**: Terraform with local state (`.azure/tf-outputs.json` has all outputs)
- **Images**: `az acr build` to private ACR (not docker push)
- **Deploy script**: `scripts/azd-deploy.sh` (builds + deploys all services)
- **Verify**: `scripts/verify-deploy.sh` (post-deploy smoke test)
- **MSAL check**: `scripts/check-msal-config.sh` (pre-deploy MSAL validation)

## Azure Resource IDs

| Resource | Name | Resource Group |
|----------|------|----------------|
| ACR | wordgamedevacr | wordgame-dev-rg |
| Container App Env | edge | wordgame-dev-rg |
| WAF App | word-game-waf | wordgame-dev-rg |
| Web App | word-game-web | wordgame-dev-rg |
| API App | word-game-api | wordgame-dev-rg |
| Agent App | word-game-agent | wordgame-dev-rg |
| Cosmos DB | (from tf-outputs) | wordgame-dev-rg |
| Key Vault | (from tf-outputs) | wordgame-dev-rg |

## Entra ID Configuration

| App | Client ID | Purpose |
|-----|-----------|---------|
| Web (SPA) | b4d29652-ff30-43ea-90f6-830cc340f866 | MSAL browser auth |
| API | 16f3fd41-cddd-44fb-a149-14314e62f7a8 | Token validation |
| Tenant | d52a6857-5f44-4f8f-bcc8-420952d3225d | Directory |

- Authority: `https://login.microsoftonline.com/d52a6857-5f44-4f8f-bcc8-420952d3225d`
- API Scope: `api://16f3fd41-cddd-44fb-a149-14314e62f7a8/access_as_user`
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

WAF FQDN: `word-game-waf.salmonpond-f3d80363.centralus.azurecontainerapps.io`

## Key File Locations

### word-game-harness
| Purpose | Path |
|---------|------|
| Azure config | azure.yaml |
| Terraform outputs | .azure/tf-outputs.json |
| Deploy all services | scripts/azd-deploy.sh |
| Post-deploy verify | scripts/verify-deploy.sh |
| E2E authenticated tests | scripts/e2e-test.sh |
| MSAL config check | scripts/check-msal-config.sh |
| Guardrails | .copilot/guardrails/pattern.yml, nfr.yml |
| API contract | .contracts/game-api.yml |
| WebSocket contract | .contracts/websocket-api.yml |
| Agent contract | .contracts/agent-api.yml |

### word-game-web
| Purpose | Path |
|---------|------|
| MSAL auth hook | src/hooks/useAuth.ts |
| App entry (MSAL config) | src/App.tsx |
| API client | src/services/apiClient.ts |
| Vite config | vite.config.ts |
| Dockerfile | Dockerfile |
| Nginx config | nginx.conf |
| Index HTML | index.html |
| Package manifest | package.json |

### word-game-api
| Purpose | Path |
|---------|------|
| FastAPI main | app/main.py |
| Pydantic models | app/models.py |
| Auth/JWT validation | app/auth.py |
| Route handlers | app/routes/ |
| Dockerfile | Dockerfile |
| Requirements | requirements.txt |
| Tests | tests/ |

### word-game-waf
| Purpose | Path |
|---------|------|
| Nginx config template | docker/nginx/nginx.conf.template |
| ModSecurity overrides | docker/modsecurity/modsecurity-override.conf |
| Dockerfile | Dockerfile |
| Health check script | docker/scripts/health-check.sh |

### word-game-agent
| Purpose | Path |
|---------|------|
| Agent main | app/main.py |
| Foundry client | app/foundry_client.py |
| Dockerfile | Dockerfile |
| Requirements | requirements.txt |
| Tests | tests/ |

### word-game-infra
| Purpose | Path |
|---------|------|
| Main config | main.tf |
| Container Apps | containerapps.tf |
| Networking/VNet | networking.tf |
| ACR | acr.tf |
| Cosmos DB | cosmos.tf |
| Key Vault | keyvault.tf |
| Identity/UAMI | identity.tf |
| Variables | variables.tf |
| Outputs | outputs.tf |

## Deployment Wait Pattern (NO sleep!)

Instead of `sleep N && az containerapp revision show ...`, use:

```bash
# Poll until revision is running (max 120s)
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

1. **MSAL redirectUri**: Must use `window.location.origin` at runtime, NOT `VITE_*` env var
2. **Vite build args**: `VITE_*` must be ARG→ENV BEFORE `npm run build` in Dockerfile
3. **Token fallback**: Use `acquireTokenPopup`, NEVER `acquireTokenRedirect` (causes infinite loops)
4. **API field names**: Always snake_case in request bodies (Python/Pydantic convention)
5. **WAF min replicas**: Must be 1 (not 0) — it's the public entry point
6. **OWASP CRS 911100**: Blocks PUT/PATCH/DELETE by default — must exclude for API paths
7. **ACR access**: `public_network_access_enabled=true` needed for `az acr build`
8. **nginx map_hash_bucket_size**: Set to 128 for long ACA FQDNs

## Child Agent Dispatch Model

Use `phase="full"` for the standard workflow (preferred):
```
start_child_agents_batch(repos=["word-game-api", "word-game-web"], phase="full")
```

This runs a single copilot session per repo that:
1. Picks first item from `work/todo/`
2. **Specialist phase**: Implements the change
3. **Critic phase**: 5-tier review (objective → requirements → failure modes → security → architecture)
4. If FAIL → specialist fixes, re-validates (up to 3 cycles per item)
5. If PASS → moves to `work/done/`, picks next item from `work/todo/`
6. Exits when `work/todo/` is empty

Available phases:
- `phase="full"` — integrated specialist+critic loop (default for production use)
- `phase="specialist"` — specialist only, moves to `work/ready-for-review/`
- `phase="critic"` — critic only, picks from `work/ready-for-review/`
