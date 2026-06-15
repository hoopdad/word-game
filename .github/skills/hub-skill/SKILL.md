# MCAPS Hub Skill

## Purpose

This skill scaffolds a complete Azure hub foundation Terraform module, aligned with the patterns in
`mikeo-lab/hub`, with optional components controlled by user intent.

**AVM-First Approach:** Generated code **prioritizes Azure Verified Modules (AVM)** over base `azurerm` resources. AVMs provide curated, tested, best-practice implementations with built-in security, compliance, and operational defaults. The skill generates code using:

- `avm/res/network/virtual_network` — replaces `azurerm_virtual_network` + `azurerm_subnet` + `azurerm_network_security_group`
- `avm/res/network/private_dns_zone` — replaces direct `azurerm_private_dns_zone` management
- `avm/res/network/private_dns_resolver` — replaces `azurerm_private_dns_resolver` + endpoint configuration
- `avm/res/monitor/private_link_scope` — replaces `azurerm_monitor_private_link_scope` + manual PE setup

**Fallback:** Resources without AVM equivalents (e.g., VPN Gateway, Azure Monitor alerts) use base `azurerm` resources.

It writes Terraform files to disk, then runs `terraform fmt -recursive`, `terraform init`, and
`terraform validate` to ensure generated code is well-formed.

It never runs `terraform plan` or `terraform apply`.

---

## Invocation

Use this skill when a user asks to:

- Create or scaffold a hub network
- Build a hub module for hub-and-spoke networking
- Add DNS resolver, private DNS, LAW/AMPLS, VPN, or NVA to a hub
- Set up a central Azure networking baseline using Terraform

---

## Feature Gates (intent-driven)

Include features by default unless explicitly disabled, with these hard gates:

- VPN (`vpn.tf`, VPN alerts) is **optional**:
  - Include only if user explicitly asks for `S2S VPN` or `P2S VPN`
- Linux firewall/NVA (`linux-fw.tf`, UDR patterns) is **optional**:
  - Include only if user explicitly asks for Linux-based firewall/NVA

Always include by default:

- Hub resource group
- Hub VNet(s), subnets, NSGs, and peering model
- Private DNS zones and VNet links
- Private DNS resolver and inbound endpoint
- Log Analytics Workspace (LAW)
- Azure Monitor Private Link Scope (AMPLS) + PE + scoped services
- Core diagnostics settings

---

## Inputs (ENV-first)

Prefer environment variables first. If missing, generate a `terraform.tfvars.template` and ask the
user to fill in values.

Required inputs:

- `TF_VAR_hub_subscription_id`
- `TF_VAR_hub_resource_group_name`
- `TF_VAR_hub_region`
- `TF_VAR_hub_vnet_name`
- `TF_VAR_hub_law_name`
- `TF_VAR_dns_resolver_name`
- `TF_VAR_lab_prefix`

Optional inputs:

- `TF_VAR_hub_resource_group_region`
- `TF_VAR_private_dns_zones` (or defaults from template)
- `TF_VAR_vpn_client_address_pool`
- `TF_VAR_lab_admin_object_id`
- `TF_VAR_vpn_gateway_alert_email_receivers` (JSON-encoded)

Never hard-code subscription IDs in generated `.tf` files.

---

## Output Structure

Write files to user-selected output folder (default: `./hub/`):

- `providers.tf` — Terraform version, AVM provider requirements, azurerm provider config
- `variables.tf` — All input variables with descriptions; no defaults for subscription IDs
- `terraform.tfvars` (or `terraform.tfvars.template` if required values missing)
- `data.tf` — Data sources for external resources (if needed)
- `vnet.tf` — AVM VirtualNetwork modules + hub-to-hub peering
- `dns.tf` — AVM PrivateDnsZone + AVM PrivateDnsResolver modules
- `law.tf` — Log Analytics Workspace + role assignments (base resources)
- `ampls.tf` — AVM MonitorPrivateLinkScope module
- `monitoring.tf` — Diagnostic settings, metric alerts (base resources)
- `outputs.tf` — VNet IDs, DNS resolver endpoints, LAW ID
- `vpn.tf` *(optional per feature gate)* — VPN Gateway + connections (base resources)
- `linux-fw.tf` *(optional per feature gate)* — Linux firewall VM + routing (base resources)
- `README.md` *(generated usage notes for this module only)*

**No submodules are scaffolded by this skill.** All AVM modules are sourced directly from the
Azure Terraform Registry (registry.terraform.io).

---

## Provider Rules

Generate provider config supporting both AVM modules and fallback `azurerm` resources:

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
}

provider "azurerm" {
  use_cli                         = true
  subscription_id                 = var.hub_subscription_id
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
```

`variables.tf` must include:

```hcl
variable "hub_subscription_id" {
  description = "Azure subscription ID for hub resources."
  type        = string
  sensitive   = true
}
```

---

## Hub Generation Model (AVM-Preferred)

### 1. Core network (`vnet.tf`) — AVM VirtualNetwork Module

**Preferred:** Use `avm/res/network/virtual_network` module for each hub VNet.

```hcl
module "hub_vnet" {
  source = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.3"

  for_each = var.hub_vnets

  name                = each.value.name
  address_space       = each.value.address_space
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location

  subnets = each.value.subnets  # Map of subnet name → {address_prefix, delegation, nsg_rules}

  # NSGs managed by AVM; disable for manual mgmt
  create_network_security_group = true

  tags = var.hub_tags
}
```

**Hub-to-Hub peering:** Use `azurerm_virtual_network_peering` directly (no AVM equivalent yet).

### 2. DNS Zones (`dns.tf`) — AVM PrivateDnsZone Module

**Preferred:** Use `avm/res/network/private_dns_zone` for each private DNS zone.

```hcl
module "private_dns_zones" {
  source = "Azure/avm-res-network-private-dns-zone/azurerm"
  version = "~> 0.1"

  for_each = var.private_dns_zones

  name                = each.key
  resource_group_name = azurerm_resource_group.hub_rg.name

  # VNet links via AVM variable
  virtual_networks_to_link = {
    for vnet_key, vnet_mod in module.hub_vnet : vnet_key => {
      vnet_id = vnet_mod.resource_id
      registration_enabled = false
    }
  }

  tags = var.hub_tags
}
```

### 3. DNS Resolver (`dns.tf`) — AVM PrivateDnsResolver Module

**Preferred:** Use `avm/res/network/private_dns_resolver` (combines resolver + inbound endpoint).

```hcl
module "dns_resolver" {
  source = "Azure/avm-res-network-private-dns-resolver/azurerm"
  version = "~> 0.1"

  name                = var.dns_resolver_name
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location

  inbound_endpoints = {
    inbound = {
      name    = "${var.lab_prefix}-dns-inbound-ep"
      subnet_id = module.hub_vnet["primary"].subnets["dns-resolver-subnet"].id
    }
  }

  tags = var.hub_tags
}
```

### 4. Logging (`law.tf`) — Managed by Baseline Config

For Log Analytics Workspace and role assignments:
- **Preferred:** Use `avm/res/monitor/log-analytics-workspace` (not yet widely available)
- **Fallback:** Use `azurerm_log_analytics_workspace` + `azurerm_role_assignment` (base resources)

```hcl
resource "azurerm_log_analytics_workspace" "law" {
  name                = var.hub_law_name
  location            = azurerm_resource_group.hub_rg.location
  resource_group_name = azurerm_resource_group.hub_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.hub_tags
}

resource "azurerm_role_assignment" "law_admin" {
  count = var.hub_admin_object_id != null ? 1 : 0

  scope           = azurerm_log_analytics_workspace.law.id
  role_definition_name = "Log Analytics Contributor"
  principal_id    = var.hub_admin_object_id
}
```

### 5. Monitoring Private Path (`ampls.tf`) — AVM MonitorPrivateLinkScope Module

**Preferred:** Use `avm/res/monitor/private_link_scope` (manages AMPLS + private endpoint + DNS integration).

```hcl
module "ampls" {
  source = "Azure/avm-res-monitor-private-link-scope/azurerm"
  version = "~> 0.2"

  name                = var.hub_ampls_name
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location

  # Link LAW to AMPLS via AVM variable
  scoped_services = {
    law = {
      resource_id = azurerm_log_analytics_workspace.law.id
    }
  }

  # Private endpoint configuration (AVM handles DNS zone groups)
  private_endpoint = {
    name                 = "${var.lab_prefix}-ampls-pe"
    subnet_id            = module.hub_vnet["primary"].subnets["ampls-subnet"].id
    dns_zone_resource_ids = [module.private_dns_zones["privatelink.monitor.azure.com"].id]
  }

  tags = var.hub_tags
}
```

### 6. Monitoring and Alerts (`monitoring.tf`)

Diagnostic settings and metric alerts (no AVM yet; use base `azurerm` resources):

```hcl
resource "azurerm_monitor_diagnostic_setting" "vnet_diagnostics" {
  for_each = module.hub_vnet

  name               = "${each.value.name}-diag"
  target_resource_id = each.value.resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
```

### 7. Optional VPN (`vpn.tf`) — No AVM; Use Base Resources

Only if intent includes `S2S VPN` or `P2S VPN`.

Generate:

- `azurerm_virtual_network_gateway` (no AVM available)
- Local network gateway and connection blocks (when S2S requested)
- P2S configuration and address pool (when P2S requested)
- Optional VPN alerts via `azurerm_monitor_metric_alert`

### 8. Optional Linux Firewall/NVA (`linux-fw.tf`) — Base Resources

Only if intent includes Linux firewall/NVA.

Generate:

- `azurerm_linux_virtual_machine` (no AVM at time of writing)
- `azurerm_network_interface`
- Routing table and route entries for forced tunneling
- NSG rules for management/data paths

---

## Terraform Validation (mandatory)

After writing files:

```bash
cd {hub_output_dir}
terraform fmt -recursive
terraform init
terraform validate
```

If any command fails, fix generated code and rerun until all pass.
Do not report completion until validation passes.

---

## Safety and Constraints

- Never run `terraform plan` or `terraform apply`
- Never embed subscription IDs, tenant IDs, secrets, or passwords in generated files
- Prefer managed identity and private endpoints over public exposure
- Keep VPN and NVA optional and intent-gated
- Keep all generated names parameterized from `lab_prefix`
- Preserve typed variables and deterministic locals

---

## Completion Output

When done, report:

- Output directory path
- Files generated
- Which optional features were included/excluded and why
- `terraform fmt/init/validate` pass/fail status
- Any manual follow-up required from user
