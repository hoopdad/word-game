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

# Link the spoke VNet to every hub private DNS zone so private endpoints in
# the spoke (ACR, Key Vault, Cosmos, Storage, etc.) resolve correctly from
# within the spoke, including from the self-hosted runner VM.
resource "azurerm_private_dns_zone_virtual_network_link" "hub_to_spoke" {
  for_each = toset(var.private_dns_zone_names)

  provider              = azurerm.hub
  name                  = "mikeo-lab-infra-vnet-${each.value}-link"
  resource_group_name   = var.hub_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# Legacy internal-subdomain zones (external_enabled=false format). Kept for reference.
# Apps now use external_enabled=true, so the root-domain zones below are the active path.
resource "azurerm_private_dns_zone" "aca_internal" {
  name                = "internal.${module.aca_env.default_domain}"
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

resource "azurerm_private_dns_zone_virtual_network_link" "aca_internal_hub" {
  name                  = "mikeo-lab-hub-vnet-internal.wonderfulsea-3a2d2678.centralus-link"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.aca_internal.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_a_record" "aca_internal_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.aca_internal.name
  resource_group_name = azurerm_resource_group.spoke.name
  ttl                 = 300
  records             = [module.aca_env.static_ip_address]
}

# Root-domain ACA env zone — used when ingress.external_enabled=true on an internal ACA env.
# FQDN format: <app>.<env-default-domain> (no .internal. prefix).
resource "azurerm_private_dns_zone" "aca_ext" {
  name                = module.aca_env.default_domain
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca_ext_spoke" {
  name                  = "lnk-aca-spoke"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.aca_ext.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca_ext_hub" {
  name                  = "lnk-aca-hub"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.aca_ext.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_a_record" "aca_ext_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.aca_ext.name
  resource_group_name = azurerm_resource_group.spoke.name
  ttl                 = 300
  records             = [module.aca_env.static_ip_address]
}

# Legacy WAF internal-subdomain zone.
resource "azurerm_private_dns_zone" "waf_internal" {
  name                = "internal.${module.waf_env.default_domain}"
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "waf_internal" {
  name                  = "link-waf-${local.spoke_prefix}"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.waf_internal.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "waf_internal_hub" {
  name                  = "mikeo-lab-hub-vnet-internal.delightfulbush-d019f7e0.central-link"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.waf_internal.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_a_record" "waf_internal_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.waf_internal.name
  resource_group_name = azurerm_resource_group.spoke.name
  ttl                 = 300
  records             = [module.waf_env.static_ip_address]
}

# Root-domain WAF env zone — used when ingress.external_enabled=true.
# FQDN format: <app>.<waf-env-default-domain>.
resource "azurerm_private_dns_zone" "waf_ext" {
  name                = module.waf_env.default_domain
  resource_group_name = azurerm_resource_group.spoke.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "waf_ext_spoke" {
  name                  = "lnk-waf-spoke"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.waf_ext.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "waf_ext_hub" {
  name                  = "lnk-waf-hub"
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.waf_ext.name
  virtual_network_id    = data.azurerm_virtual_network.hub.id
  registration_enabled  = false
}

resource "azurerm_private_dns_a_record" "waf_ext_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.waf_ext.name
  resource_group_name = azurerm_resource_group.spoke.name
  ttl                 = 300
  records             = [module.waf_env.static_ip_address]
}

# Import blocks for hub DNS VNet links created manually before Terraform managed them.
import {
  to = azurerm_private_dns_zone_virtual_network_link.hub_to_spoke["privatelink.azurecr.io"]
  id = "/subscriptions/0ff111e2-f787-4beb-900b-01bc2c83aec2/resourceGroups/mikeo-lab-rg/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io/virtualNetworkLinks/mikeo-lab-infra-vnet-privatelink.azurecr.io-link"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.hub_to_spoke["privatelink.vaultcore.azure.net"]
  id = "/subscriptions/0ff111e2-f787-4beb-900b-01bc2c83aec2/resourceGroups/mikeo-lab-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net/virtualNetworkLinks/mikeo-lab-infra-vnet-privatelink.vaultcore.azure.net-link"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.hub_to_spoke["privatelink.documents.azure.com"]
  id = "/subscriptions/0ff111e2-f787-4beb-900b-01bc2c83aec2/resourceGroups/mikeo-lab-rg/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com/virtualNetworkLinks/mikeo-lab-infra-vnet-privatelink.documents.azure.com-link"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.hub_to_spoke["privatelink.blob.core.windows.net"]
  id = "/subscriptions/0ff111e2-f787-4beb-900b-01bc2c83aec2/resourceGroups/mikeo-lab-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/mikeo-lab-infra-vnet-privatelink.blob.core.windows.net-link"
}

import {
  to = azurerm_private_dns_zone_virtual_network_link.aca_internal_hub
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/internal.wonderfulsea-3a2d2678.centralus.azurecontainerapps.io/virtualNetworkLinks/mikeo-lab-hub-vnet-internal.wonderfulsea-3a2d2678.centralus-link"
}

import {
  to = azurerm_private_dns_zone_virtual_network_link.waf_internal_hub
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/internal.delightfulbush-d019f7e0.centralus.azurecontainerapps.io/virtualNetworkLinks/mikeo-lab-hub-vnet-internal.delightfulbush-d019f7e0.central-link"
}

# Import blocks for root-domain ACA/WAF zones and links created manually.
import {
  to = azurerm_private_dns_zone.aca_ext
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/wonderfulsea-3a2d2678.centralus.azurecontainerapps.io"
}
import {
  to = azurerm_private_dns_a_record.aca_ext_wildcard
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/wonderfulsea-3a2d2678.centralus.azurecontainerapps.io/A/*"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.aca_ext_spoke
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/wonderfulsea-3a2d2678.centralus.azurecontainerapps.io/virtualNetworkLinks/lnk-aca-spoke"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.aca_ext_hub
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/wonderfulsea-3a2d2678.centralus.azurecontainerapps.io/virtualNetworkLinks/lnk-aca-hub"
}

import {
  to = azurerm_private_dns_zone.waf_ext
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/delightfulbush-d019f7e0.centralus.azurecontainerapps.io"
}
import {
  to = azurerm_private_dns_a_record.waf_ext_wildcard
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/delightfulbush-d019f7e0.centralus.azurecontainerapps.io/A/*"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.waf_ext_spoke
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/delightfulbush-d019f7e0.centralus.azurecontainerapps.io/virtualNetworkLinks/lnk-waf-spoke"
}
import {
  to = azurerm_private_dns_zone_virtual_network_link.waf_ext_hub
  id = "/subscriptions/8a2ded28-6d3b-4ff5-9eee-0056ee08b371/resourceGroups/mikeo-lab-infra-rg/providers/Microsoft.Network/privateDnsZones/delightfulbush-d019f7e0.centralus.azurecontainerapps.io/virtualNetworkLinks/lnk-waf-hub"
}

