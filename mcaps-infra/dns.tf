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
