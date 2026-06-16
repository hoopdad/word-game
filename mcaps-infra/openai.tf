# Optional Azure OpenAI + AI Foundry placeholder resources. Disabled by default.
# Enabling these also requires adding a Cognitive Services private endpoint and a
# privatelink.openai.azure.com / privatelink.cognitiveservices.azure.com hub zone
# (tracked as a follow-up) so the agent can reach the account privately.
resource "azurerm_cognitive_account" "openai" {
  count                         = var.enable_openai_resources ? 1 : 0
  name                          = local.openai_account_name
  location                      = var.spoke_region
  resource_group_name           = azurerm_resource_group.spoke.name
  kind                          = "OpenAI"
  sku_name                      = var.openai_sku_name
  custom_subdomain_name         = local.openai_subdomain
  public_network_access_enabled = false
  tags                          = local.common_tags
}

resource "azapi_resource" "ai_foundry_project" {
  count                     = var.enable_foundry_resources && var.enable_openai_resources ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = local.ai_project_suffix
  parent_id                 = azurerm_cognitive_account.openai[0].id
  location                  = var.spoke_region
  schema_validation_enabled = false

  body = {
    properties = {
      description = "Placeholder AI Foundry project for ${local.spoke_prefix}"
    }
  }
}

resource "azapi_resource" "openai_deployment_placeholder" {
  count                     = var.enable_foundry_resources && var.enable_openai_resources ? 1 : 0
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name                      = var.openai_deployment_name
  parent_id                 = azurerm_cognitive_account.openai[0].id
  schema_validation_enabled = false

  body = {
    sku = {
      name = var.openai_deployment_sku
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.openai_model_name
        version = var.openai_model_version
      }
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }
}
