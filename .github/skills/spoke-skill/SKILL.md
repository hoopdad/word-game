# MCAPS Spoke Skill

## Purpose

This skill provisions a fully integrated Azure hub-and-spoke **networking layer** for a new spoke
workload. It writes Terraform files to disk, reads the shared CIDR registry from GitHub, claims
the next available address block, and produces a separate `_hub-todo/` folder for hub-side
changes that a human must review and apply.

**AVM-First Approach:** Generated code **prioritizes Azure Verified Modules (AVM)** over base `azurerm` resources. AVMs provide production-tested, best-practice implementations with built-in security, compliance, and operational defaults.

Key AVM modules used in spoke generation:
- `avm/res/network/virtual_network` — spoke VNet, subnets, NSGs, diagnostics
- `avm/res/network/private_dns_zone` — spoke-side DNS zone links (coordination with hub via data sources)
- `avm/res/network/private_endpoint` *(optional)* — private endpoints for workload services
- `avm/res/monitor/private_link_scope` — linking Application Insights to hub AMPLS (for ML spoke type)

**Fallback:** Spoke-type-specific resources (AKS, ML workspace, etc.) use base `azurerm` resources where AVMs are not yet available.

It **does not** run Terraform, CI/CD pipelines, or shell commands. Its output is files on disk
only.

---

## When To Invoke

Use this skill when the user asks any of:

- "Create a new spoke" / "Add a spoke to the hub"
- "Wire up a new workload to our hub network"
- "I need a new VNet connected to the hub with private DNS and logging"
- "Create networking for a new AKS / ML / generic spoke"

---

## Prerequisites Checklist

Before generating any files, confirm the following with the user:

| Item | How to supply |
|------|---------------|
| **Spoke subscription ID** | `TF_VAR_spoke_subscription_id` env var, or user provides inline |
| **Hub subscription ID** | `TF_VAR_hub_subscription_id` env var, or user provides inline |
| **Hub resource group name** | `TF_VAR_hub_resource_group_name` env var |
| **Hub VNet name** | `TF_VAR_hub_vnet_name` env var |
| **Hub Log Analytics Workspace name** | `TF_VAR_hub_law_name` env var |
| **Hub AMPLS name** | `TF_VAR_hub_ampls_name` env var |
| **Lab prefix** | `TF_VAR_lab_prefix` env var (e.g. `myorg-lab`). Applied to all resource names as `{lab_prefix}-{spoke_short_name}-{type}`. |
| **CIDR registry GitHub URL** | User provides (e.g. `https://github.com/org/repo`) |
| **Spoke short name** | User provides (e.g. `avd`, `myapp`) — used in all resource names |
| **Spoke type** | `generic` \| `aks` \| `ml` — affects subnet scaffolding |
| **Azure region** | User provides or `TF_VAR_spoke_region` env var |
| **Output directory** | Default: `<spoke-short-name>/` in the current repo root |

Prefer ENV vars over asking. If an ENV var is set, read it silently. Only prompt for items
that cannot be inferred or discovered.

---

## CIDR Registry Format

The skill expects a file named `cidr.yaml` at the root of the CIDR GitHub repository. If the
repository does not yet have `cidr.yaml`, the skill proposes the format below and asks the user
to confirm before creating it.

### Proposed `cidr.yaml` schema

```yaml
# cidr.yaml  — network address registry
# ----------------------------------------
meta:
  supernet: "10.0.0.0/16"       # Master supernet all spokes are carved from
  vpn_p2s_pool: "172.20.0.0/27" # P2S VPN client pool (non-routable to spokes)
  home_lan: "10.1.0.0/24"       # On-prem LAN behind VPN gateway

hub_vnets:
  - name: "{lab_prefix}-hub-vnet"    # e.g. myorg-lab-hub-vnet
    region: eastus2
    cidr: "10.0.0.0/22"
    purpose: hub-eus2
  - name: "{lab_prefix}-hub-vnet-cus"  # e.g. myorg-lab-hub-vnet-cus
    region: centralus
    cidr: "10.4.0.0/22"
    purpose: hub-cus

reserved_blocks:
  # Non-routable / infrastructure ranges that must not be used for spoke VNets
  - cidr: "192.168.0.0/16"
    purpose: "AKS internal service CIDR"
  - cidr: "172.20.0.0/27"
    purpose: "VPN P2S client pool"

spoke_vnets:
  - name: "{lab_prefix}-mlws-vnet"   # replace {lab_prefix} with your actual prefix
    region: centralus
    cidr: "10.0.4.0/24"
    spoke_module: ml-workspace
    status: active
    subnets:
      - name: private-endpoint-subnet
        cidr: "10.0.4.0/25"

  - name: "{lab_prefix}-aks-vnet"
    region: centralus
    cidr: "10.0.5.0/24"
    spoke_module: aks
    status: active
    subnets:
      - name: aks-subnet
        cidr: "10.0.5.0/25"
      - name: pep-subnet
        cidr: "10.0.5.128/25"

  - name: "{lab_prefix}-vm-vnet"
    region: centralus
    cidr: "10.0.6.0/25"
    spoke_module: virtualmachine
    status: active
    subnets:
      - name: vm-subnet
        cidr: "10.0.6.0/25"

  # Add new spoke entries below; the skill appends them automatically
```

### Reading the CIDR registry (GitHub)

The skill uses the `gh` CLI (user must be logged in) to read `cidr.yaml`:

```bash
gh api repos/{owner}/{repo}/contents/cidr.yaml \
  --jq '.content' | base64 -d > /tmp/cidr.yaml
```

Parse the file to find the next **available /24** inside the supernet that does not overlap any
entry in `hub_vnets` + `spoke_vnets` + `reserved_blocks`. Present the chosen CIDR to the user
before writing any files.

### Writing back to GitHub

After generating all Terraform files, the skill appends the new spoke entry to `cidr.yaml` and
commits it:

```bash
# 1. Encode updated file
base64 -w0 /tmp/cidr-updated.yaml > /tmp/cidr-b64.txt

# 2. Get current file SHA (required for update)
SHA=$(gh api repos/{owner}/{repo}/contents/cidr.yaml --jq '.sha')

# 3. Commit
gh api --method PUT repos/{owner}/{repo}/contents/cidr.yaml \
  -f message="spoke/{spoke_name}: claim CIDR {cidr}" \
  -f content="$(cat /tmp/cidr-b64.txt)" \
  -f sha="$SHA"
```

Inform the user that the CIDR has been committed, then continue.

---

## Step-by-Step Execution

### Step 1 — Collect inputs

Read all available `TF_VAR_*` environment variables. For any missing required value, ask the
user once (batch all missing questions together). Do not ask for items already available.

```bash
# Read all TF_VAR_ inputs at once:
echo "spoke_subscription_id=${TF_VAR_spoke_subscription_id}"
echo "hub_subscription_id=${TF_VAR_hub_subscription_id}"
echo "hub_resource_group_name=${TF_VAR_hub_resource_group_name}"
echo "hub_vnet_name=${TF_VAR_hub_vnet_name}"
echo "hub_law_name=${TF_VAR_hub_law_name}"
echo "hub_ampls_name=${TF_VAR_hub_ampls_name}"
echo "lab_prefix=${TF_VAR_lab_prefix}"
echo "spoke_region=${TF_VAR_spoke_region}"
```

Derive the following locals from user answers:

| Local | Derivation |
|-------|-----------|
| `lab_prefix` | `TF_VAR_lab_prefix` env var — no default; required |
| `spoke_prefix` | `{lab_prefix}-{spoke_short_name}` |
| `spoke_rg_name` | `{spoke_prefix}-rg` |
| `spoke_vnet_name` | `{spoke_prefix}-vnet` |
| `output_dir` | `./{spoke_short_name}/` (or user override) |

### Step 2 — Read CIDR registry and claim next /24

1. Run the `gh` command above to fetch `cidr.yaml`.
2. Parse all occupied CIDRs in `hub_vnets`, `spoke_vnets`, and `reserved_blocks`.
3. Walk available /24 blocks inside `meta.supernet` in ascending order.
4. Return the first block with no overlap.
5. Display to user: `"Claiming {cidr} for spoke VNet {spoke_vnet_name}. Confirm? [y/n]"`
6. On confirmation, proceed. On rejection, let user specify their preferred CIDR.

### Step 3 — Generate subnet plan

Propose subnets based on `spoke_type`:

#### generic
| Subnet | Default size | Purpose |
|--------|-------------|---------|
| `pep-subnet` | /26 | Private endpoints |
| `workload-subnet` | /25 | App VMs / containers |

#### ml
| Subnet | Default size | Purpose |
|--------|-------------|---------|
| `private-endpoint-subnet` | /25 | Private endpoints (ML, storage, KV, ACR) |
| `compute-subnet` | /26 | ML compute instances |

#### aks
| Subnet | Default size | Purpose |
|--------|-------------|---------|
| `aks-subnet` | /25 | Node pool CIDR |
| `pep-subnet` | /26 | Private endpoints |

Present the subnet plan to the user. Allow overrides before writing files.

#### Subnet delegations

If the spoke workload requires delegated subnets (e.g. `Microsoft.Web/serverFarms` for App
Service Environment, `Microsoft.ContainerInstance/containerGroups` for ACI,
`Microsoft.Databricks/workspaces` for Databricks), declare them separately using the
`subnet_with_delegations` variable. The network module treats delegated subnets as a distinct
collection so the `delegation {}` block can be applied without affecting plain subnets.

Ask the user: *"Does this spoke need any delegated subnets? If so, provide the subnet name,
CIDR, service delegation name, and required actions."*

Example entry for `terraform.tfvars`:

```hcl
subnet_with_delegations = {
  "ase-subnet" = {
    address_cidr = "10.X.Y.128/26"
    delegation = {
      "ase-delegation" = {
        service_delegation_name = "Microsoft.Web/hostingEnvironments"
        actions                 = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }
}
```

If no delegations are needed, set `subnet_with_delegations = {}` in `terraform.tfvars`.

### Step 4 — Discover hub state via az CLI

Run the following read-only `az` commands to learn hub details needed as data source inputs.
Do **not** modify any hub resources here.

```bash
# Confirm hub VNet exists and get ID
az network vnet show \
  --subscription "$TF_VAR_hub_subscription_id" \
  --resource-group "$TF_VAR_hub_resource_group_name" \
  --name "$TF_VAR_hub_vnet_name" \
  --query "{id:id, addressSpace:addressSpace}" -o json

# List existing private DNS zones in hub RG
az network private-dns zone list \
  --subscription "$TF_VAR_hub_subscription_id" \
  --resource-group "$TF_VAR_hub_resource_group_name" \
  --query "[].name" -o json

# Get DNS resolver inbound endpoint IP (for DNS server config reference)
az dns-resolver inbound-endpoint list \
  --subscription "$TF_VAR_hub_subscription_id" \
  --resource-group "$TF_VAR_hub_resource_group_name" \
  --dns-resolver-name "$(az dns-resolver list \
       --subscription "$TF_VAR_hub_subscription_id" \
       --resource-group "$TF_VAR_hub_resource_group_name" \
       --query '[0].name' -o tsv)" \
  --query '[0].ipConfigurations[0].privateIpAddress' -o tsv

# Confirm AMPLS exists
az monitor private-link-scope show \
  --subscription "$TF_VAR_hub_subscription_id" \
  --resource-group "$TF_VAR_hub_resource_group_name" \
  --name "$TF_VAR_hub_ampls_name" \
  --query "{name:name, id:id}" -o json
```

Store the results to populate `terraform.tfvars` and data source lookups. Do not hard-code any
subscription IDs or resource IDs in .tf files; use variables or data sources.

#### Step 4b — DNS zone gap analysis

After listing existing zones, build the set of zones **required** by the spoke type:

| Spoke type | Required zones |
|-----------|---------------|
| `generic` | `privatelink.blob.core.windows.net`, `privatelink.vaultcore.azure.net`, `privatelink.monitor.azure.com`, `privatelink.oms.opinsights.azure.com`, `privatelink.ods.opinsights.azure.com`, `privatelink.agentsvc.azure-automation.net` |
| `ml` | All generic zones plus: `privatelink.api.azureml.ms`, `privatelink.notebooks.azure.net`, `privatelink.azurecr.io`, `privatelink.file.core.windows.net` |
| `aks` | All generic zones plus: `privatelink.<region>.azmk8s.io` |

If the user declares additional private endpoints (e.g. for Azure SQL, Service Bus, Event Hub,
Cognitive Services, etc.), append the corresponding zone to the required set. A full reference:

| Service | Zone |
|---------|------|
| Azure SQL | `privatelink.database.windows.net` |
| Azure Service Bus | `privatelink.servicebus.windows.net` |
| Azure Event Hub | `privatelink.servicebus.windows.net` |
| Azure Cosmos DB (SQL) | `privatelink.documents.azure.com` |
| Azure Container Registry | `privatelink.azurecr.io` |
| Azure Cognitive / AI Services | `privatelink.cognitiveservices.azure.com` |
| Azure OpenAI | `privatelink.openai.azure.com` |
| Azure App Service | `privatelink.azurewebsites.net` |
| Azure Redis Cache | `privatelink.redis.cache.windows.net` |
| Azure Kubernetes Service | `privatelink.<region>.azmk8s.io` |
| Azure Data Factory | `privatelink.datafactory.azure.net` |
| Azure Synapse | `privatelink.sql.azuresynapse.net` |

Compute the **gap**: `required_zones − existing_hub_zones`.

- If the gap is **empty**: proceed. The `private_dns_zones` map in `terraform.tfvars` is
  populated with all required zones; all will be found by `data.azurerm_private_dns_zone`.
- If the gap is **non-empty**: those zones do not yet exist in the hub. They cannot be created
  in the spoke module. Do the following:
  1. Populate `private_dns_zones` in `terraform.tfvars` with **only the existing zones**.
     Add the missing zones as comments with a `# PENDING HUB CREATION` marker.
  2. Generate `_hub-todo/hub-new-dns-zones.tf.snippet` (see Step 6 below).
  3. Tell the user clearly: *"The following zones must be created in the hub before the spoke
     can link to them. Apply `_hub-todo/hub-new-dns-zones.tf.snippet` first, then re-run
     `terraform plan` on the spoke."*

### Step 5 — Write spoke Terraform files

Write the following files to `{output_dir}/`. All variable values go in `terraform.tfvars`.
Resource names follow the pattern `{spoke_prefix}-{resource-type-abbreviation}`.

#### `providers.tf`

> **Note — variables in provider blocks:** Terraform 1.x fully supports `var.*` references
> inside `provider` blocks. The `subscription_id` values below are read from input variables
> which Terraform resolves before configuring providers. Supply them via `TF_VAR_*` environment
> variables; they are never stored in `.tf` files or `terraform.tfvars`.
>
> **AVM Support:** AVM modules for spoke generation require explicit provider configuration
> and may depend on provider plugin versions ≥ 4.0.

```hcl
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "local" {}
}

provider "azurerm" {
  use_cli                         = true
  subscription_id                 = var.spoke_subscription_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azurerm" {
  alias           = "hub"
  use_cli         = true
  subscription_id = var.hub_subscription_id

  features {}
}
```

#### `variables.tf`

Declare all variables with descriptions. Never assign defaults for subscription IDs. Always
declare:

```hcl
variable "spoke_subscription_id" {
  description = "Azure subscription ID for this spoke."
  type        = string
  sensitive   = true
}

variable "hub_subscription_id" {
  description = "Azure subscription ID for the hub."
  type        = string
  sensitive   = true
}

variable "hub_resource_group_name" {
  description = "Name of the hub resource group."
  type        = string
}

variable "hub_vnet_name" {
  description = "Name of the hub virtual network."
  type        = string
}

variable "hub_law_name" {
  description = "Name of the hub Log Analytics Workspace."
  type        = string
}

variable "hub_ampls_name" {
  description = "Name of the hub Azure Monitor Private Link Scope."
  type        = string
}

variable "spoke_region" {
  description = "Azure region for spoke resources."
  type        = string
}

variable "spoke_prefix" {
  description = "Prefix for all spoke resource names, formed as {lab_prefix}-{spoke_short_name} (e.g. myorg-lab-avd)."
  type        = string
}

variable "app_resource_group_name" {
  description = "Name of the spoke resource group."
  type        = string
}

variable "app_vnet_name" {
  description = "Name of the spoke virtual network."
  type        = string
}

variable "app_vnet_address_space" {
  description = "Address space list for the spoke VNet."
  type        = list(string)
}

variable "app_subnets" {
  description = "Map of subnet name to address prefix list."
  type        = map(list(string))
}

variable "private_dns_zones" {
  description = "Map of private DNS zone FQDN to friendly name for VNet linking."
  type        = map(string)
}

variable "app_tags" {
  description = "Tags applied to all spoke resources."
  type        = map(string)
  default     = {}
}

variable "use_remote_gateways" {
  description = "Whether the spoke should use the hub VPN gateway (true for EUS2, false for CUS)."
  type        = bool
  default     = true
}

variable "spoke_route_table_id" {
  description = "Route table ID for NVA-routed CUS spokes. Null = no UDR applied."
  type        = string
  default     = null
}

variable "lab_prefix" {
  description = "Shared prefix for all resource names in this lab (e.g. myorg-lab). Combined with spoke_short_name to form spoke_prefix."
  type        = string
}

variable "subnet_with_delegations" {
  description = "Map of delegated subnet names to their CIDR and service delegation config. Use for subnets that require a service delegation (e.g. ASE, ACI, Databricks). Leave empty if not needed."
  type = map(object({
    address_cidr = string
    delegation = map(object({
      service_delegation_name = string
      actions                 = list(string)
    }))
  }))
  default = {}
}
```

#### `terraform.tfvars`

Populate with all non-sensitive values derived from steps 1–4. Leave subscription IDs as
**empty strings** with a comment directing the user to set `TF_VAR_spoke_subscription_id` and
`TF_VAR_hub_subscription_id`.

```hcl
# -------------------------------------------------------
# REQUIRED: set these as env vars, not in this file
# export TF_VAR_spoke_subscription_id="<YOUR_SPOKE_SUB_ID>"
# export TF_VAR_hub_subscription_id="<YOUR_HUB_SUB_ID>"
# -------------------------------------------------------

hub_resource_group_name = "<DISCOVERED_VALUE>"
hub_vnet_name           = "<DISCOVERED_VALUE>"
hub_law_name            = "<DISCOVERED_VALUE>"
hub_ampls_name          = "<DISCOVERED_VALUE>"

spoke_region            = "<USER_PROVIDED>"
lab_prefix              = "<LAB_PREFIX>"           # e.g. myorg-lab  (from TF_VAR_lab_prefix)
spoke_prefix            = "<LAB_PREFIX>-<SHORT_NAME>"
app_resource_group_name = "<LAB_PREFIX>-<SHORT_NAME>-rg"
app_vnet_name           = "<LAB_PREFIX>-<SHORT_NAME>-vnet"
app_vnet_address_space  = ["<CLAIMED_CIDR>"]
use_remote_gateways     = true

app_subnets = {
  # <SUBNET_PLAN_FROM_STEP_3>
}

private_dns_zones = {
  # Map of hub-hosted DNS zone FQDNs to link to this spoke VNet.
  # Add entries matching the zones discovered in Step 4.
  # Example:
  "privatelink.blob.core.windows.net"              = "blob"
  "privatelink.vaultcore.azure.net"                = "kv"
  "privatelink.monitor.azure.com"                  = "monitor"
  "privatelink.oms.opinsights.azure.com"           = "oms"
  "privatelink.ods.opinsights.azure.com"           = "ods"
  "privatelink.agentsvc.azure-automation.net"      = "agentsvc"
}

# Delegated subnets — set to {} if not needed, or populate for delegations:
subnet_with_delegations = {}

app_tags = {
  environment = "lab"
  spoke       = "<SHORT_NAME>"
  managed_by  = "terraform"
}
```

#### `data.tf`

```hcl
data "azurerm_client_config" "current" {}

# Hub VNet (for peering)
data "azurerm_virtual_network" "hub" {
  provider            = azurerm.hub
  name                = var.hub_vnet_name
  resource_group_name = var.hub_resource_group_name
}

# Hub Log Analytics Workspace (centralized logging, used by AVM diagnostics)
data "azurerm_log_analytics_workspace" "law" {
  provider            = azurerm.hub
  name                = var.hub_law_name
  resource_group_name = var.hub_resource_group_name
}

# Hub AMPLS (for linking spoke Application Insights to hub monitoring)
data "azurerm_monitor_private_link_scope" "ampls" {
  provider            = azurerm.hub
  name                = var.hub_ampls_name
  resource_group_name = var.hub_resource_group_name
}

# Hub private DNS zones (looked up for AVM VNet DNS linking)
data "azurerm_private_dns_zone" "dnszone" {
  provider            = azurerm.hub
  for_each            = var.private_dns_zones
  name                = each.key
  resource_group_name = var.hub_resource_group_name
}
```

#### `main.tf`

**Preferred approach — AVM VirtualNetwork Module:**

```hcl
resource "azurerm_resource_group" "spoke_rg" {
  name     = var.app_resource_group_name
  location = var.spoke_region
  tags     = var.app_tags
}

module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.3"

  name                = var.app_vnet_name
  address_space       = var.app_vnet_address_space
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = azurerm_resource_group.spoke_rg.location

  subnets = local.spoke_subnets_with_delegations

  create_network_security_group = true
  
  diagnostic_settings = {
    to_law = {
      name                           = "${var.app_vnet_name}-diag"
      log_analytics_workspace_id     = data.azurerm_log_analytics_workspace.law.id
      log_analytics_workspace_name   = data.azurerm_log_analytics_workspace.law.name
      log_analytics_workspace_resource_group_name = data.azurerm_log_analytics_workspace.law.resource_group_name
      
      enabled_log = [{ category_group = "allLogs" }]
      enabled_metric = [{ category = "AllMetrics" }]
    }
  }

  tags = var.app_tags
}

# Hub VNet peering (spoke → hub direction)
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "${var.app_vnet_name}-to-hub"
  resource_group_name       = azurerm_resource_group.spoke_rg.name
  virtual_network_name      = module.spoke_vnet.name
  remote_virtual_network_id = data.azurerm_virtual_network.hub.id
  
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_remote_gateways
}

# Link spoke VNet to hub DNS zones (coordinates with hub-side DNS links from _hub-todo/)
module "spoke_dns_links" {
  source  = "Azure/avm-res-network-private-dns-zone/azurerm"
  version = "~> 0.1"
  
  for_each = data.azurerm_private_dns_zone.dnszone

  name                = each.value.name
  resource_group_name = data.azurerm_private_dns_zone.dnszone[each.key].resource_group_name
  
  virtual_networks_to_link = {
    spoke = {
      vnet_id              = module.spoke_vnet.resource_id
      registration_enabled = false
    }
  }
  
  tags = var.app_tags
  
  depends_on = [data.azurerm_private_dns_zone.dnszone]
}
```

#### `logs.tf`

**Diagnostic settings now handled by AVM VNet module** (see `main.tf` diagnostic_settings block).
This file is used for workload-specific logging resources only.

**For AKS spokes:**

```hcl
resource "azurerm_kubernetes_cluster" "spoke_aks" {
  # ... cluster configuration ...
  
  oms_agent {
    log_analytics_workspace_id = data.azurerm_log_analytics_workspace.law.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks_diagnostics" {
  name               = "${var.spoke_prefix}-aks-diag"
  target_resource_id = azurerm_kubernetes_cluster.spoke_aks.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.law.id

  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}
```

**For ML spokes:**

```hcl
resource "azurerm_application_insights" "spoke_ai" {
  name                       = "${var.spoke_prefix}-ai"
  location                   = var.spoke_region
  resource_group_name        = azurerm_resource_group.spoke_rg.name
  application_type           = "web"
  workspace_id               = data.azurerm_log_analytics_workspace.law.id
  internet_ingestion_enabled = false
  internet_query_enabled     = false
  tags                       = var.app_tags
}
```

#### `ampls.tf`

Link the spoke's Application Insights (if present) to the hub AMPLS via base resources (no AVM yet):

```hcl
# Only include this block if the spoke type creates Application Insights (ML spokes).
resource "azurerm_monitor_private_link_scoped_service" "spoke_app_insights" {
  provider = azurerm.hub

  name                = "${var.spoke_prefix}-ai-ampls-link"
  resource_group_name = var.hub_resource_group_name
  scope_name          = data.azurerm_monitor_private_link_scope.ampls.name
  linked_resource_id  = azurerm_application_insights.spoke_ai.id
}
```

#### `outputs.tf`

```hcl
output "spoke_vnet_id" {
  description = "Resource ID of the spoke VNet."
  value       = module.spoke_network.vnet
}

output "spoke_subnet_map" {
  description = "Map of subnet name to subnet ID."
  value       = module.spoke_network.subnet_map
}

output "spoke_resource_group_id" {
  description = "Resource ID of the spoke resource group."
  value       = azurerm_resource_group.spoke_rg.id
}
```

### Step 6 — Write `_hub-todo/` folder

The hub VNet peering **from** the hub side, and new DNS zone links for the spoke VNet, must be
applied in the hub module. Write these as **separate, ready-to-apply Terraform snippets** in
`_hub-todo/` at the repo root. Include a `README.md` that explains exactly what to do.

#### `_hub-todo/README.md`

````markdown
# Hub Changes Required for Spoke: {spoke_short_name}

These resources must be added to the hub Terraform module (`hub/`) before or immediately
after the spoke is first applied. The spoke's VNet peering (`spoke → hub`) is already
managed by the spoke module via `modules/network/hub-peering.tf`. The items below handle
the **hub side** of the integration.

## Files in this folder

| File | What it does |
|------|-------------|
| `hub-dns-links.tf.snippet` | Links all hub private DNS zones to the new spoke VNet |
| `hub-new-dns-zones.tf.snippet` | Creates any DNS zones not yet present in the hub (only generated when gaps were found in Step 4b) |
| `hub-peering-override.tf.snippet` | Only needed if you want explicit hub-side peering config |

## Steps

1. If `hub-new-dns-zones.tf.snippet` is present, **apply it first** (copy into `hub/dns.tf`,
   plan and apply the hub) before touching the spoke.
2. Review `hub-dns-links.tf.snippet` and copy into `hub/dns.tf`.
3. Run `terraform fmt` from the `hub/` directory.
4. Run `terraform plan -out=tfplan` and review the output.
5. Run `terraform apply tfplan`.
6. Delete or archive this `_hub-todo/` folder once applied.

## Notes

- The spoke VNet ID needed for DNS links is an **output** of the spoke module.
  Run `terraform output spoke_vnet_id` from the spoke directory first, then
  substitute the value into the snippets below.
- Never hard-code resource IDs. Use a `data "azurerm_virtual_network"` source in `hub/`
  that targets the spoke by name/RG, or pass the ID via a variable.
````

#### `_hub-todo/hub-dns-links.tf.snippet`

```hcl
# ---------------------------------------------------------------------------
# Add to hub/dns.tf
# Hub private DNS zone links for spoke: {spoke_vnet_name}
# ---------------------------------------------------------------------------
# These link every hub-hosted private DNS zone to the new spoke VNet so that
# private endpoint DNS names resolve from within the spoke.
#
# BEFORE applying: replace <SPOKE_VNET_ID> with the output of:
#   terraform -chdir=../{spoke_short_name} output -raw spoke_vnet_id
#
# NOTE: if hub-new-dns-zones.tf.snippet was also generated, apply that first.
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone_virtual_network_link" "{spoke_short_name}_dns_links" {
  provider = azurerm  # hub provider context

  for_each = toset([
    # Populated by skill from Step 4 / Step 4b — zones that already exist in hub:
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    # <SKILL APPENDS ADDITIONAL EXISTING ZONES HERE>
  ])

  name                  = "{spoke_vnet_name}-${each.value}-link"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = "<SPOKE_VNET_ID>"  # replace before applying
  registration_enabled  = false
}
```

#### `_hub-todo/hub-new-dns-zones.tf.snippet` *(only generated when Step 4b finds gaps)*

```hcl
# ---------------------------------------------------------------------------
# Add to hub/dns.tf
# New private DNS zones required for spoke: {spoke_vnet_name}
# ---------------------------------------------------------------------------
# These zones do not yet exist in the hub. They must be created and applied
# BEFORE running `terraform plan` on the spoke module, because the spoke's
# data.azurerm_private_dns_zone lookups will fail if zones are absent.
#
# After applying, also copy the corresponding entries into
# hub-dns-links.tf.snippet so the new spoke VNet is linked.
# ---------------------------------------------------------------------------

local {
  # <SKILL FILLS THIS IN from the gap set identified in Step 4b>
  new_dns_zones_for_{spoke_short_name} = toset([
    # Example (replace with actual missing zones):
    # "privatelink.database.windows.net",
    # "privatelink.servicebus.windows.net",
  ])
}

resource "azurerm_private_dns_zone" "new_for_{spoke_short_name}" {
  for_each            = local.new_dns_zones_for_{spoke_short_name}
  name                = each.key
  resource_group_name = var.hub_resource_group_name
  tags                = var.hub_tags

  soa_record {
    email        = "azureprivatedns-host.microsoft.com"
    expire_time  = 2419200
    minimum_ttl  = 10
    refresh_time = 3600
    retry_time   = 300
    ttl          = 3600
  }
}
```

After the hub applies these zones, the spoke's `terraform.tfvars` should be updated to
move the `# PENDING HUB CREATION` zone entries out of comments and into the active
`private_dns_zones` map.

---

## Spoke-Type Variant Notes

### generic

No additional files beyond the base set. Add workload-specific `private_endpoint` and
`azurerm_monitor_diagnostic_setting` blocks in `main.tf` or a dedicated `perivateendpoints.tf`.

### ml

Add the following extra files:

- `keyvault.tf` — Key Vault with `public_network_access_enabled = false` and a private endpoint
  in `pep-subnet`.
- `storage.tf` — Storage account with `public_network_access_enabled = false`.
- `acr.tf` — Container Registry (Premium SKU for private endpoint support).
- `ml.tf` — `azurerm_machine_learning_workspace` with `public_network_access_enabled = false`.
- `logs.tf` — Application Insights (`internet_ingestion_enabled = false`,
  `internet_query_enabled = false`), wired to hub LAW.
- `ampls.tf` — Link spoke AI to hub AMPLS (via `azurerm.hub` provider).

All private endpoints go in `pep-subnet`. DNS zone entries for ML:

```
privatelink.api.azureml.ms
privatelink.notebooks.azure.net
privatelink.azurecr.io
privatelink.blob.core.windows.net
privatelink.file.core.windows.net
privatelink.vaultcore.azure.net
```

### aks

Add:

- `aks.tf` — `azurerm_kubernetes_cluster` with:
  - `default_node_pool.vnet_subnet_id` → `module.spoke_network.subnet_map["aks-subnet"]`
  - `network_profile.service_cidr` set to a non-overlapping range (e.g. `192.168.0.0/16`)
  - `network_profile.dns_service_ip` = `192.168.0.10`
  - `oms_agent` add-on: `log_analytics_workspace_id = data.azurerm_log_analytics_workspace.law.id`
  - `identity.type = "SystemAssigned"`
  - `private_cluster_enabled = true`
  - `dns_prefix` = `{spoke_prefix}`
- `logs.tf` — diagnostic settings for the AKS cluster resource.

DNS zones for AKS private cluster:

```
privatelink.<region>.azmk8s.io
```

---

### Step 7 — Format, initialize, and validate the spoke module

After all files are written, run these three commands **from within the spoke output
directory**. These are the only Terraform commands the skill executes automatically.

```bash
cd {output_dir}

# 1. Format — rewrites all .tf files to canonical style.
#    Failures here indicate a code generation bug; report the offending file.
terraform fmt -recursive

# 2. Init — downloads providers and the modules/network module.
#    Uses the local backend; no remote state is configured.
#    Pass -backend=false only if hub connectivity is not available yet.
terraform init

# 3. Validate — checks schema and references without calling any Azure API.
#    A clean validate confirms the HCL is structurally correct.
#    It does NOT verify that hub data sources resolve (that requires plan).
terraform validate
```

**Handling failures:**

| Command | Failure | Action |
|---------|---------|--------|
| `terraform fmt` | Output shows diff | Regenerate or patch the offending file and re-run. |
| `terraform init` | Provider download error | Check internet access or proxy settings. Re-run after fixing. |
| `terraform init` | Module source not found | Confirm `../modules/network` path is correct relative to the spoke folder. |
| `terraform validate` | `Unknown variable` | A variable is declared in `variables.tf` but missing from `terraform.tfvars`. Add it. |
| `terraform validate` | `An argument named X is not expected` | The network module version does not support that argument. Remove or update the module. |
| `terraform validate` | `data source X not found` | Provider version too old. Check `required_providers` version constraint. |

If `terraform validate` exits with a non-zero code, fix the generated files and re-run
validate before reporting completion. Do **not** proceed to display the Output Summary
until validate passes cleanly.

---

## Security Baseline (Applied to All Spokes)

These defaults are **required** and must appear in every generated file:

| Control | Implementation | AVM Module |
|---------|----------------|------------|
| No public IPs by default | Omit `public_ip_address_id` unless a NAT gateway PIP is explicit | AVM VNet module |
| `public_network_access_enabled = false` | Set on KV, Storage, ML, ACR, App Insights | Base `azurerm` + AVM PE module |
| NSG on every subnet | AVM VNet module auto-generates; custom rules in NSG resource | AVM VNet module |
| Diagnostic settings | AVM VNet module wires to hub LAW; workload resources use base resources | AVM VNet + base `azurerm` |
| Private endpoints | AVM PrivateEndpoint module for all PaaS services in `pep-subnet` | `avm/res/network/private-endpoint` |
| Managed Identity | `SystemAssigned` on compute; no connection strings in config | Base `azurerm` (AKS, VMs) |
| TLS 1.2+ | `min_tls_version = "TLS1_2"` on storage / KV | Base `azurerm` |
| DNS zone integration | AVM VNet module vnet_links for spoke-to-zone linking | `avm/res/network/private-dns-zone` |
| VNet peering | Base `azurerm_virtual_network_peering` (no AVM yet) | Base `azurerm` |

---

## Output Summary

When the skill completes, it should display a summary like:

```
Spoke module written to: ./{spoke_short_name}/
  providers.tf
  variables.tf
  terraform.tfvars     ← fill in subscription IDs via TF_VAR env vars
  data.tf
  main.tf
  logs.tf
  ampls.tf             ← (if Application Insights present)
  outputs.tf

Validation results:
  terraform fmt      PASS
  terraform init     PASS
  terraform validate PASS

Hub changes (review & apply manually):
  _hub-todo/README.md
  _hub-todo/hub-dns-links.tf.snippet
  _hub-todo/hub-new-dns-zones.tf.snippet  ← (only if Step 4b found missing zones)

CIDR registry updated: cidr.yaml committed to GitHub
  Claimed: {cidr} for {spoke_vnet_name}

Next steps:
  1. Export TF_VAR_spoke_subscription_id and TF_VAR_hub_subscription_id (if not already set)
  2. If _hub-todo/hub-new-dns-zones.tf.snippet exists, apply it in hub/ first
  3. cd {spoke_short_name} && terraform plan -out=tfplan
  4. Review the plan carefully, then: terraform apply tfplan
  5. terraform output -raw spoke_vnet_id
  6. Substitute the VNet ID into _hub-todo/hub-dns-links.tf.snippet
  7. Apply hub DNS link changes from _hub-todo/
```

---

## Constraints and Rules

- **Never store subscription IDs in `.tf` files.** Always use variables marked `sensitive = true`
  and instruct the user to supply them via `TF_VAR_*` env vars.
- **Permitted Terraform commands (run automatically in Step 7):** `terraform fmt`, `terraform init`,
  `terraform validate`. These are safe read/write-local operations with no Azure API side-effects.
- **Never run `terraform plan` or `terraform apply`.** Plan contacts Azure APIs and apply makes
  changes to live infrastructure — both require human review and explicit user action.
- **Never modify hub Terraform files directly.** All hub-side changes go in `_hub-todo/`.
- **New private DNS zones always belong to the hub.** If a spoke needs a zone that does not
  yet exist, generate `_hub-todo/hub-new-dns-zones.tf.snippet` and mark the corresponding
  entries in `private_dns_zones` with `# PENDING HUB CREATION`. Never create `azurerm_private_dns_zone`
  resources inside a spoke module.
- **Never change `public_network_access` flags** on existing resources to perform lookups.
  Use `data` sources and cross-subscription provider aliases instead.
- **Always use `../modules/network`** for VNet, subnet, peering, and DNS linking. Do not
  duplicate this logic inline.
- **All resource names must follow the `{lab_prefix}-<short-name>-<type>` pattern** and use
  variables, never hard-coded strings. `lab_prefix` comes from `TF_VAR_lab_prefix`; never
  embed a literal organisation prefix in the skill.
- **No interactive Terraform variable prompts.** Every variable must have either a default
  or a value in `terraform.tfvars` (or be supplied via `TF_VAR_*`).
- Run `terraform fmt -recursive`, `terraform init`, and `terraform validate` automatically
  after writing all files (Step 7). Do not report completion until all three pass.
