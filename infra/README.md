# Azure Infrastructure (Terraform)

This directory contains Terraform IaC for the baseline Azure platform used by the word game stack.

## What this deploys

- Resource group
- Azure Container Apps managed environment
- Standalone VNet with delegated ACA subnets and NSGs
- Public WAF Container App front door
- Three placeholder container apps:
  - `web`
  - `api`
  - `agent`
- Azure Container Registry (ACR, Premium for private endpoints / ACR build)
- User-assigned managed identity
- Optional RBAC scaffolding (disabled by default):
  - `AcrPull` for the managed identity on ACR
  - `Cosmos DB Account Reader Role` for the managed identity on Cosmos DB account
  - `Cognitive Services OpenAI User` for the managed identity on OpenAI account
- Cosmos DB account + SQL database + SQL container placeholders
- Cosmos DB / ACR / Key Vault / Storage private endpoints and private DNS zones
- Azure Key Vault and Storage account placeholders
- Optional Azure OpenAI account (`azurerm_cognitive_account`, disabled by default)
- Optional Azure AI Foundry project/deployment placeholders (`azapi_resource`, disabled by default)

## Network architecture

All resources except the WAF container app are locked down to private networking.

```text
VNet: 10.0.0.0/16
  snet-waf  (10.0.0.0/23)   — external ACA env hosting only the WAF proxy
  snet-aca  (10.0.8.0/21)   — internal ACA env (api, web, agent) — no public ingress
  snet-pe   (10.0.4.0/24)   — private endpoints for ACR, Cosmos, Key Vault, Storage
  snet-mgmt (10.0.5.0/24)   — reserved for future management bastion
```

**Traffic flow:**

```text
Internet → ca-waf-wordgame-dev (HTTPS, port 443)
           nginx + OWASP ModSecurity CRS (OWASP Top 10 blocking rules)
           /api/* → ca-api-wordgame-dev (internal FQDN, HTTPS)
           /*     → ca-web-wordgame-dev (internal FQDN, HTTPS)
```

**NSG enforcement:**
- `snet-waf` NSG: allows HTTP/HTTPS from Internet; allows AzureLoadBalancer; denies all other inbound.
- `snet-aca` NSG: allows traffic only from `snet-waf` (port 8080/80/443) and AzureLoadBalancer; denies direct Internet.
- `snet-pe` NSG: allows only VNet-internal traffic; denies Internet inbound and outbound.

**Private endpoints:** ACR, Cosmos DB, Key Vault, Storage all have private endpoints in `snet-pe` with private DNS zones auto-registered. ACR requires Premium SKU for private endpoint support.

**CI/CD note:** The CD workflow uses `az acr build` (ACR Tasks) instead of `docker push`. ACR Tasks are a trusted Azure service and bypass the private-network restriction (`network_rule_bypass_option = "AzureServices"`). For ACR admin credentials used by `az containerapp registry set`, `admin_enabled = true` is required.

## Regional defaults and overrides

The default (and required baseline) deployment region is **Central US (`centralus`)** for ACA, Cosmos DB, Azure OpenAI/Foundry, and other regional services via:

- `variable "location"` default in `variables.tf`
- `terraform.tfvars.example`

Override options:

1. Edit `terraform.tfvars`:
   ```hcl
   location = "eastus2"
   ```
2. Use CLI var:
   ```bash
   terraform plan -var "location=eastus2"
   ```
3. Use env var:
   ```bash
   export TF_VAR_location=eastus2
   ```

## Required inputs and secrets

Copy and edit the example vars file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Populate at least:

- `name_prefix`
- `environment`
- `tags`
- `enable_role_assignments` (`false` by default; set `true` only with User Access Administrator/Owner)
- `enable_foundry_resources` (`false` by default; set `true` after confirming supported API/model SKU in your region)
- `enable_openai_resources` (`false` by default; set `true` only when AOAI is required and available)

No static secrets are committed. Terraform auth should come from Azure CLI or OIDC-based service principal federation:

- `az login` (local interactive), or
- `ARM_USE_OIDC=true`
- `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`

## Deploy

```bash
az provider register --namespace Microsoft.App --wait
terraform init
terraform plan
terraform apply
```

For the private ACR flow, the CD workflow uses `az acr build` instead of local Docker push.

## Validation commands used for this task

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

If `terraform init` or `terraform validate` fails in your environment due to provider download/auth constraints, capture and follow the exact error message shown by Terraform.
