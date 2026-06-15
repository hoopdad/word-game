spoke_region             = "centralus"
lab_prefix               = "mikeo-lab"
spoke_short_name         = "infra"
spoke_type               = "generic"
cidr_registry_repo       = "https://github.com/hoopdad/mikeo-hub"
spoke_vnet_address_space = ["10.0.28.0/24"]
workload_subnet_cidr     = "10.0.28.0/25"
pep_subnet_cidr          = "10.0.28.128/26"
private_dns_zone_names = [
  "privatelink.blob.core.windows.net",
  "privatelink.vaultcore.azure.net",
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
]
use_remote_gateways = true

tags = {
  environment = "lab"
  managed_by  = "terraform"
  module      = "spoke"
}
