output "spoke_resource_group_name" {
  description = "Spoke resource group name."
  value       = azurerm_resource_group.spoke.name
}

output "spoke_vnet_name" {
  description = "Spoke VNet name."
  value       = azurerm_virtual_network.spoke.name
}

output "spoke_vnet_id" {
  description = "Spoke VNet ID."
  value       = azurerm_virtual_network.spoke.id
}

output "spoke_subnet_ids" {
  description = "Spoke subnet IDs."
  value = {
    workload = azurerm_subnet.workload.id
    pep      = azurerm_subnet.pep.id
  }
}

output "hub_vnet_id" {
  description = "Hub VNet ID."
  value       = data.azurerm_virtual_network.hub.id
}

output "hub_law_id" {
  description = "Hub Log Analytics workspace ID."
  value       = data.azurerm_log_analytics_workspace.hub.id
}

output "hub_ampls_id" {
  description = "Hub Azure Monitor Private Link Scope ID."
  value       = local.hub_ampls_id
  sensitive   = true
}

output "hub_private_dns_zone_ids" {
  description = "Existing hub private DNS zone IDs keyed by zone name."
  value       = local.hub_private_dns_zone_ids
}
