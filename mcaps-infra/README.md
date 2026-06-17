# mcaps-infra — word-game spoke (AVM-first)

Canonical Azure infrastructure for the **word-game** workload. This is a hub-and-spoke
*spoke* connected to the existing `mikeo-lab` hub. It supersedes the retired standalone
`infra/` stack. Resources prefer **Azure Verified Modules (AVM)**; only the four
Container Apps are bespoke (see below).

## Network allocation

Spoke VNet `10.0.28.0/24`, peered to the hub:

| Subnet            | CIDR             | Purpose                                            |
| ----------------- | ---------------- | -------------------------------------------------- |
| `aca-subnet`      | `10.0.28.0/27`   | Internal Container Apps env (delegated `Microsoft.App/environments`) |
| `waf-subnet`      | `10.0.28.32/27`  | Private WAF Container Apps env (delegated)         |
| `pep-subnet`      | `10.0.28.64/26`  | Private endpoints (ACR, Key Vault, Cosmos, Storage)|
| `workload-subnet` | `10.0.28.128/25` | Reserved / management                              |

## What is included

- Spoke resource group, VNet, subnets, NSGs, hub peering (bespoke spoke networking).
- Hub private DNS zone lookups + Log Analytics / AMPLS lookups (data sources).
- **AVM** modules: user-assigned identity, Azure Container Registry, Key Vault,
  Cosmos DB (SQL), two Container Apps managed environments, optional Storage,
  and all private endpoints.
- **Bespoke** `azurerm_container_app` x4 (`web`, `api`, `agent`, `waf`) with
  `lifecycle { ignore_changes = [image] }` because CD updates images out-of-band
  via `az containerapp update`. AVM's container-app module can't express that.
- Internal-env default-domain private DNS zone created in the spoke + wildcard A
  record so the private WAF env can resolve internal app FQDNs.
- Optional, flag-gated Azure OpenAI / AI Foundry resources.

## Prerequisites (hub side — apply BEFORE the first spoke apply)

Private DNS zones are hub-owned. Keep zone creation in hub Terraform and link the
spoke VNet to those existing hub zones. Use `_hub-todo/hub-dns-links.tf.snippet`
for the hub-side VNet links, including:

- `privatelink.azurecr.io` (ACR)
- `privatelink.documents.azure.com` (Cosmos DB)

The deploying identity also needs `sharedKeys` read on the cross-subscription hub
Log Analytics workspace (managed envs reference it by `resource_id`).

## Remote state backend

State lives in an azurerm backend (no more local-state import gymnastics). CD runs
`scripts/bootstrap-tfstate.sh` to create the RG + storage account + container
idempotently, then `terraform init -backend-config=...`. Required repo variable:

| Variable             | Default                  | Notes                                   |
| -------------------- | ------------------------ | --------------------------------------- |
| `TF_STATE_SA`        | *(required)*             | Globally-unique storage account name    |
| `TF_STATE_RG`        | `mikeo-lab-tfstate-rg`   | State resource group                    |
| `TF_STATE_CONTAINER` | `tfstate`                | Blob container                          |
| `TF_STATE_KEY`       | `wordgame-spoke.tfstate` | State blob key                          |

Subscription IDs are supplied via `TF_VAR_spoke_subscription_id` /
`TF_VAR_hub_subscription_id` (env / `.env`), never hard-coded in `.tf` files.

## Feature flags (`terraform.tfvars`)

All default **off** so the stack can be applied incrementally as hub prerequisites
and cross-resource access grants land:

| Flag                       | Effect                                                  |
| -------------------------- | ------------------------------------------------------- |
| `enable_role_assignments`  | UAMI role grants (AcrPull, Cosmos, OpenAI) + GitHub OIDC AcrPush on ACR. **Required** for MI-based Container App image pulls. |
| `enable_storage`           | AVM storage account + blob private endpoint             |
| `enable_openai_resources`  | Azure OpenAI cognitive account                          |
| `enable_foundry_resources` | AI Foundry project + deployment (azapi)                 |
| `enable_self_hosted_runner`| Runner networking support in `workload-subnet` (VM is provisioned with Azure CLI) |

> Container Apps pull images using the UAMI managed identity (`AcrPull` role).
> The `registry` block on each Container App binds the UAMI to ACR, eliminating
> the need for admin credentials at pull time. CD builds images locally with
> Docker (`--platform linux/amd64`) and pushes via `az acr login` (caller's
> Azure identity). The ACR remains private (public network disabled) with
> `export_policy_enabled = true` and `network_rule_bypass_option = AzureServices`
> so trusted Azure services can pull through the private endpoint.
> Set `enable_role_assignments = true` to create the UAMI AcrPull grant.
> The admin user is kept as a fallback and can be disabled once MI auth is
> confirmed working end-to-end.

## Teardown of the legacy stack

The old `infra/` stack (resource group `rg-wordgame-dev`) is retired. Tear it down
via the manual, environment-gated **Destroy legacy infra** workflow
(`.github/workflows/tf-destroy.yml`), which runs `scripts/destroy-old-infra.sh`.
That script refuses to delete the spoke, state, or hub resource groups.

## Local workflow

```bash
cd mcaps-infra
terraform fmt -recursive
terraform init -backend=false   # validate only; CD uses the real backend
terraform validate
```
