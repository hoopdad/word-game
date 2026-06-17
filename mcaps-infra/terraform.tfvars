spoke_region       = "centralus"
lab_prefix         = "mikeo-lab"
spoke_short_name   = "infra"
spoke_type         = "generic"
cidr_registry_repo = "https://github.com/hoopdad/mikeo-hub"

# Existing hub (mikeo-lab) resource identifiers consumed via data sources.
# Subscription IDs are NOT set here; they come from TF_VAR_* env / .env.
hub_resource_group_name = "mikeo-lab-rg"
hub_vnet_name           = "mikeo-lab-hub-vnet"
hub_law_name            = "mikeo-lab-hub-law"
hub_ampls_name          = "mikeo-lab-ampls"

# Spoke VNet 10.0.28.0/24 carved into four subnets:
#   aca-subnet      10.0.28.0/27    internal Container Apps env (delegated)
#   waf-subnet      10.0.28.32/27   private WAF Container Apps env (delegated)
#   pep-subnet      10.0.28.64/26   private endpoints
#   workload-subnet 10.0.28.128/25  reserved / management
spoke_vnet_address_space = ["10.0.28.0/24"]
aca_subnet_cidr          = "10.0.28.0/27"
waf_subnet_cidr          = "10.0.28.32/27"
pep_subnet_cidr          = "10.0.28.64/26"
workload_subnet_cidr     = "10.0.28.128/25"

# Hub private DNS zones consumed by the spoke private endpoints.
# These zones are owned in the hub and linked to the spoke VNet from hub-side
# Terraform/snippets (see _hub-todo/hub-dns-links.tf.snippet).
private_dns_zone_names = [
  "privatelink.blob.core.windows.net",
  "privatelink.vaultcore.azure.net",
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
  "privatelink.azurecr.io",
  "privatelink.documents.azure.com",
]

use_remote_gateways = true

# Workload toggles (default off until hub prerequisites and access grants exist).
enable_role_assignments   = true
enable_openai_resources   = false
enable_foundry_resources  = false
enable_storage            = false
enable_self_hosted_runner = true

tags = {
  environment = "lab"
  managed_by  = "terraform"
  module      = "spoke"
  workload    = "word-game"
}
