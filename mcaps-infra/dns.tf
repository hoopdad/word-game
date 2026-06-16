data "azurerm_private_dns_zone" "hub" {
  for_each = toset(var.private_dns_zone_names)

  provider            = azurerm.hub
  name                = each.value
  resource_group_name = var.hub_resource_group_name
}

locals {
  hub_private_dns_zone_ids = {
    for zone_name, zone in data.azurerm_private_dns_zone.hub : zone_name => zone.id
  }
}

# Internal Container Apps environment default-domain zone. Linked to the spoke
# VNet so the private WAF environment can resolve the internal app FQDNs.
resource "azurerm_private_dns_zone" "aca_internal" {
  name                = module.aca_env.default_domain
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca_internal" {
  name                  = "link-aca-${local.spoke_prefix}"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.aca_internal.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_a_record" "aca_internal_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.aca_internal.name
  resource_group_name = azurerm_resource_group.spoke.name
  ttl                 = 300
  records             = [module.aca_env.static_ip_address]
}
