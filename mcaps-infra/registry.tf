module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

  location            = var.spoke_region
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.spoke.name

  sku                           = var.acr_sku
  public_network_access_enabled = false
  export_policy_enabled         = true
  zone_redundancy_enabled       = false
  # Admin user enabled so CD can authenticate the Container Apps registry with
  # admin credentials (az containerapp registry set). Acceptable for this
  # private (PE-only) lab registry; switch to UAMI AcrPull once role
  # assignments are enabled (enable_role_assignments = true).
  admin_enabled = true


  private_endpoints = {
    registry = {
      name                          = "pe-acr-${local.spoke_prefix}"
      subnet_resource_id            = azapi_resource.subnet_pep.id
      private_dns_zone_group_name   = "default"
      private_dns_zone_resource_ids = [local.hub_private_dns_zone_ids["privatelink.azurecr.io"]]
    }
  }

  enable_telemetry = false
  tags             = local.common_tags
}
