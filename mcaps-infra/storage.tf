module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.7.2"

  count = var.enable_storage ? 1 : 0

  location  = var.spoke_region
  name      = local.storage_account
  parent_id = azurerm_resource_group.spoke.id

  account_kind                  = "StorageV2"
  account_sku_name              = "Standard_LRS"
  public_network_access_enabled = false

  network_rules = {
    bypass         = ["AzureServices"]
    default_action = "Deny"
  }

  private_endpoints = {
    blob = {
      name                          = "pe-blob-${local.spoke_prefix}"
      subnet_resource_id            = azurerm_subnet.pep.id
      subresource_name              = "blob"
      private_dns_zone_group_name   = "default"
      private_dns_zone_resource_ids = [local.hub_private_dns_zone_ids["privatelink.blob.core.windows.net"]]
    }
  }

  enable_telemetry = false
  tags             = local.common_tags
}
