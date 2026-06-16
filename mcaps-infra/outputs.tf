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

output "resource_group_name" {
  description = "Spoke resource group name (consumed by CD)."
  value       = azurerm_resource_group.spoke.name
}

output "location" {
  description = "Azure region used for the spoke workload."
  value       = var.spoke_region
}

output "acr_login_server" {
  description = "Azure Container Registry login server."
  value       = module.acr.resource.login_server
}

output "managed_identity_id" {
  description = "User-assigned managed identity resource ID."
  value       = module.uami.resource_id
}

output "container_apps_environment_id" {
  description = "Internal Container Apps environment ID."
  value       = module.aca_env.resource_id
}

output "waf_container_apps_environment_id" {
  description = "Public WAF Container Apps environment ID."
  value       = module.waf_env.resource_id
}

output "container_app_names" {
  description = "Container app names."
  value = {
    web   = azurerm_container_app.web.name
    api   = azurerm_container_app.api.name
    agent = azurerm_container_app.agent.name
    waf   = azurerm_container_app.waf.name
  }
}

output "waf_fqdn" {
  description = "Public WAF hostname."
  value       = azurerm_container_app.waf.ingress[0].fqdn
}

output "key_vault_id" {
  description = "Key Vault resource ID."
  value       = module.keyvault.resource_id
}

output "cosmos_account_name" {
  description = "Cosmos DB account name."
  value       = module.cosmos.name
}

output "cosmos_sql_database_name" {
  description = "Cosmos SQL database name."
  value       = var.cosmos_database_name
}

output "cosmos_sql_container_name" {
  description = "Cosmos SQL container name."
  value       = var.cosmos_container_name
}

output "openai_account_name" {
  description = "Azure OpenAI account name (null when disabled)."
  value       = try(azurerm_cognitive_account.openai[0].name, null)
}
