locals {
  base_name           = "${var.name_prefix}-${var.environment}"
  normalized_alnum    = join("", regexall("[a-z0-9]", lower(local.base_name)))
  normalized_dns      = join("", regexall("[a-z0-9-]", lower(local.base_name)))
  vnet_name           = "vnet-${local.base_name}"
  waf_env_name        = "cae-waf-${local.base_name}"
  waf_name            = "ca-waf-${local.base_name}"
  cosmos_account      = substr("${local.normalized_alnum}cosmos", 0, 44)
  acr_name            = substr("acr${local.normalized_alnum}", 0, 50)
  key_vault_name      = substr("kv${local.normalized_alnum}", 0, 24)
  storage_account     = substr("st${local.normalized_alnum}", 0, 24)
  openai_account_name = substr("aoai-${local.normalized_dns}", 0, 64)
  openai_subdomain    = substr("${local.normalized_dns}openai", 0, 64)
  ai_project_suffix   = substr(join("", regexall("[a-zA-Z0-9-]", "${var.ai_foundry_project_name}-${var.environment}")), 0, 64)
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.base_name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "aca_logs" {
  name                = "law-${local.base_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${local.base_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_container_registry" "acr" {
  name                          = local.acr_name
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.location
  sku                           = var.acr_sku
  admin_enabled                 = true
  public_network_access_enabled = false
  network_rule_bypass_option    = "AzureServices"
  tags                          = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.enable_role_assignments ? 1 : 0
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                          = local.cosmos_account
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg.name
  offer_type                    = var.cosmos_offer_type
  kind                          = "GlobalDocumentDB"
  public_network_access_enabled = false
  tags                          = var.tags

  consistency_policy {
    consistency_level = var.cosmos_consistency_level
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "app" {
  name                = var.cosmos_database_name
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "events" {
  name                  = var.cosmos_container_name
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.app.name
  partition_key_paths   = [var.cosmos_partition_key_path]
  partition_key_version = 1
  throughput            = 400
}

resource "azurerm_role_assignment" "cosmos_reader" {
  count                = var.enable_role_assignments ? 1 : 0
  scope                = azurerm_cosmosdb_account.cosmos.id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_container_app" "web" {
  name                         = "ca-web-${local.base_name}"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = var.tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "web"
      image  = var.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = false
    target_port      = var.container_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_container_app" "api" {
  name                         = "ca-api-${local.base_name}"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = var.tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "api"
      image  = var.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "PORT"
        value = tostring(var.container_port)
      }
    }
  }

  ingress {
    external_enabled = false
    target_port      = var.container_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_container_app" "agent" {
  name                         = "ca-agent-${local.base_name}"
  container_app_environment_id = azurerm_container_app_environment.aca_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = var.tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "agent"
      image  = var.placeholder_image
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }
}

resource "azurerm_cognitive_account" "openai" {
  count                 = var.enable_openai_resources ? 1 : 0
  name                  = local.openai_account_name
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku_name
  custom_subdomain_name = local.openai_subdomain
  tags                  = var.tags
}

resource "azurerm_role_assignment" "openai_user" {
  count                = var.enable_role_assignments && var.enable_openai_resources ? 1 : 0
  scope                = azurerm_cognitive_account.openai[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azapi_resource" "ai_foundry_project" {
  count     = var.enable_foundry_resources && var.enable_openai_resources ? 1 : 0
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.ai_project_suffix
  parent_id = azurerm_cognitive_account.openai[0].id
  location  = var.location

  schema_validation_enabled = false
  body = jsonencode({
    properties = {
      description = "Placeholder AI Foundry project for ${local.base_name}"
    }
  })
}

resource "azapi_resource" "openai_deployment_placeholder" {
  count     = var.enable_foundry_resources && var.enable_openai_resources ? 1 : 0
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = var.openai_deployment_name
  parent_id = azurerm_cognitive_account.openai[0].id

  schema_validation_enabled = false
  body = jsonencode({
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
  })
}
