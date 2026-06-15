---
name: spoke-skill
description: Scaffold an Azure hub-and-spoke workload VNet with AVM-first Terraform, CIDR allocation, peering, private DNS links, and hub-side follow-up snippets. Use when the user asks to create a spoke, add a workload VNet, wire a new app to the hub, or build an aks, ml, or generic spoke.
---

# MCAPS Spoke Skill

## Purpose

Use this skill to generate Terraform for a new spoke workload connected to an existing Azure hub.
The skill writes files only, prefers Azure Verified Modules, and keeps required hub follow-up in
separate `_hub-todo/` snippets.

Expected outcomes:

- Create the spoke VNet, subnets, NSGs, and tags.
- Peer the spoke to the hub.
- Link the spoke to existing hub private DNS zones.
- Send diagnostics to the hub Log Analytics workspace.
- For `aks` and `ml` spoke types, include workload-specific Terraform scaffolding where that template requires it.
- Emit hub-side follow-up snippets when the hub is missing required pieces.

Prefer these modules when possible:

- `Azure/avm-res-network-virtualnetwork/azurerm`
- `Azure/avm-res-network-private-dns-zone/azurerm`
- `Azure/avm-res-network-private-endpoint/azurerm`

Use base `azurerm` resources only where no suitable AVM exists.

## Invoke When

Use this skill when the user asks to:

- create a new spoke
- add a workload VNet to the hub
- build networking for a `generic`, `aks`, or `ml` spoke
- wire private DNS, logging, and peering for a new workload

## Inputs

Prefer existing `TF_VAR_*` environment variables. Ask only for missing values.

If the user needs starter files, use these bundled assets:

- [templates/cidr.yaml](templates/cidr.yaml)
- [templates/terraform.tfvars.template](templates/terraform.tfvars.template)

Required values:

- `TF_VAR_spoke_subscription_id`
- `TF_VAR_hub_subscription_id`
- `TF_VAR_hub_resource_group_name`
- `TF_VAR_hub_vnet_name`
- `TF_VAR_hub_law_name`
- `TF_VAR_hub_ampls_name`
- `TF_VAR_lab_prefix`
- `TF_VAR_spoke_short_name`
- `TF_VAR_spoke_type` as `generic`, `aks`, or `ml`
- `TF_VAR_cidr_registry_repo` as a GitHub repo URL that contains `cidr.yaml`

Optional values:

- `TF_VAR_spoke_region`
- custom output directory, otherwise `./{TF_VAR_spoke_short_name}/`
- delegated subnet requirements

Derived names:

- `spoke_prefix = {lab_prefix}-{TF_VAR_spoke_short_name}`
- `spoke_rg_name = {spoke_prefix}-rg`
- `spoke_vnet_name = {spoke_prefix}-vnet`

## Execution Rules

1. Read all available `TF_VAR_*` values first.
2. Ask once for only the missing required inputs.
3. Do not hard-code subscription IDs or resource IDs in generated `.tf` files.
4. Write files only. Do not run `terraform plan` or `terraform apply`.
5. Keep hub-side changes out of the spoke module; emit them under `_hub-todo/`.

## CIDR Allocation

The source of truth is `cidr.yaml` in the user-provided GitHub repo.

Expected top-level keys:

- `meta.supernet`
- `hub_vnets`
- `reserved_blocks`
- `spoke_vnets`

Allocation behavior:

1. Read `cidr.yaml` with `gh`.
2. Collect occupied CIDRs from `hub_vnets`, `reserved_blocks`, and `spoke_vnets`.
3. Find the first available `/24` inside `meta.supernet`.
4. Present the proposed CIDR and allow the user to override it.
5. After file generation, append the new spoke entry and commit the updated `cidr.yaml`.

If `cidr.yaml` does not exist, stop and start from
[templates/cidr.yaml](templates/cidr.yaml) before creating anything.

## Spoke Presets

Default subnet plan:

### generic

- `workload-subnet` as `/25`
- `pep-subnet` as `/26`

### aks

- `aks-subnet` as `/25`
- `pep-subnet` as `/26`

### ml

- `private-endpoint-subnet` as `/25`
- `compute-subnet` as `/26`

Always show the proposed subnet plan and allow overrides before writing files.

If delegated subnets are required, collect subnet name, CIDR, delegation name, and actions, then
emit them through `subnet_with_delegations` in `terraform.tfvars`.

## Hub Discovery

Use read-only `az` commands to confirm:

- hub VNet
- existing private DNS zones
- AMPLS instance
- DNS resolver inbound endpoint when needed for docs or outputs

Never create or modify hub resources during discovery.

## DNS Zone Gap Analysis

Base zones for every spoke:

- `privatelink.blob.core.windows.net`
- `privatelink.vaultcore.azure.net`
- `privatelink.monitor.azure.com`
- `privatelink.oms.opinsights.azure.com`
- `privatelink.ods.opinsights.azure.com`
- `privatelink.agentsvc.azure-automation.net`

Additions:

- `ml`: `privatelink.api.azureml.ms`, `privatelink.notebooks.azure.net`, `privatelink.azurecr.io`, `privatelink.file.core.windows.net`
- `aks`: `privatelink.<region>.azmk8s.io`

If extra private endpoints are requested, add the corresponding DNS zones.

When required zones are missing from the hub:

- keep only existing zones in `terraform.tfvars`
- mark missing zones as pending hub creation
- write `_hub-todo/hub-new-dns-zones.tf.snippet`
- tell the user the hub zones must be created before spoke planning can fully succeed

## Files To Generate

Write these under `./{TF_VAR_spoke_short_name}/` unless the user overrides the directory:

- `providers.tf`
- `variables.tf`
- `terraform.tfvars`
- `network.tf`
- `dns.tf`
- `monitoring.tf`
- `outputs.tf`
- `README.md`

Write hub follow-up artifacts under `./_hub-todo/`:

- `hub-dns-links.tf.snippet`
- `hub-new-dns-zones.tf.snippet` when required

## Terraform Requirements

Generated Terraform must:

- require Terraform `>= 1.9`
- use `azurerm` `~> 4.50`
- use `random` `~> 3.5` when needed
- define a primary `azurerm` provider for the spoke subscription
- define an aliased `azurerm.hub` provider for hub lookups
- keep subscription IDs supplied via variables or environment variables

## Output Expectations

The generated spoke should include:

- no public IPs by default
- NSGs on all subnets
- diagnostics to the hub LAW
- private endpoints for relevant PaaS services
- `public_network_access_enabled = false` where applicable
- managed identity where the workload type supports it

## Final Response

End with:

- the chosen CIDR
- the subnet plan
- the files written
- any `_hub-todo/` actions
- any missing hub DNS zones
- the next steps for `terraform fmt`, `terraform init`, `terraform validate`, `terraform plan`, and any required hub apply sequence