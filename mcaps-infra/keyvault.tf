module "keyvault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  location            = var.spoke_region
  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.spoke.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                      = "standard"
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      name                          = "pe-kv-${local.spoke_prefix}"
      subnet_resource_id            = azurerm_subnet.pep.id
      private_dns_zone_group_name   = "default"
      private_dns_zone_resource_ids = [local.hub_private_dns_zone_ids["privatelink.vaultcore.azure.net"]]
    }
  }

  enable_telemetry = false
  tags             = local.common_tags
}
