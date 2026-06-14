output "resource_group_name" {
  description = "Resource group name."
  value       = azurerm_resource_group.rg.name
}

output "location" {
  description = "Azure region used for deployment."
  value       = var.location
}

output "container_apps_environment_id" {
  description = "Container Apps managed environment ID."
  value       = azurerm_container_app_environment.aca_env.id
}

output "container_app_names" {
  description = "Placeholder container app names."
  value = {
    web   = azurerm_container_app.web.name
    api   = azurerm_container_app.api.name
    agent = azurerm_container_app.agent.name
  }
}

output "acr_login_server" {
  description = "ACR login server."
  value       = azurerm_container_registry.acr.login_server
}

output "managed_identity_id" {
  description = "User-assigned managed identity resource ID."
  value       = azurerm_user_assigned_identity.workload.id
}

output "cosmos_account_name" {
  description = "Cosmos DB account name."
  value       = azurerm_cosmosdb_account.cosmos.name
}

output "cosmos_sql_database_name" {
  description = "Cosmos SQL database placeholder."
  value       = azurerm_cosmosdb_sql_database.app.name
}

output "cosmos_sql_container_name" {
  description = "Cosmos SQL container placeholder."
  value       = azurerm_cosmosdb_sql_container.events.name
}

output "openai_account_name" {
  description = "Azure OpenAI account name."
  value       = try(azurerm_cognitive_account.openai[0].name, null)
}

output "ai_foundry_project_id" {
  description = "AI Foundry placeholder project resource ID."
  value       = try(azapi_resource.ai_foundry_project[0].id, null)
}
