module "uami" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.0"

  location            = var.spoke_region
  name                = "id-${local.spoke_prefix}"
  resource_group_name = azurerm_resource_group.spoke.name

  enable_telemetry = false
  tags             = local.common_tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.enable_role_assignments ? 1 : 0
  scope                = module.acr.resource_id
  role_definition_name = "AcrPull"
  principal_id         = module.uami.principal_id
}

resource "azurerm_role_assignment" "cosmos_reader" {
  count                = var.enable_role_assignments ? 1 : 0
  scope                = module.cosmos.resource_id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = module.uami.principal_id
}

resource "azurerm_role_assignment" "openai_user" {
  count                = var.enable_role_assignments && var.enable_openai_resources ? 1 : 0
  scope                = azurerm_cognitive_account.openai[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.uami.principal_id
}
