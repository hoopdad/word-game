locals {
  base_name           = "${var.name_prefix}-${var.environment}"
  normalized_alnum    = join("", regexall("[a-z0-9]", lower(local.base_name)))
  normalized_dns      = join("", regexall("[a-z0-9-]", lower(local.base_name)))
  cosmos_account      = substr("${local.normalized_alnum}cosmos", 0, 44)
  acr_name            = substr("acr${local.normalized_alnum}", 0, 50)
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

resource "azurerm_container_app_environment" "aca_env" {
  name                       = "cae-${local.base_name}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aca_logs.id
  tags                       = var.tags
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = "id-${local.base_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = local.cosmos_account
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = var.cosmos_offer_type
  kind                = "GlobalDocumentDB"
  tags                = var.tags

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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "web"
      image  = "${azurerm_container_registry.acr.login_server}/web:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "api"
      image  = "${azurerm_container_registry.acr.login_server}/api:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.workload.id
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "agent"
      image  = "${azurerm_container_registry.acr.login_server}/agent:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }
}

resource "azurerm_cognitive_account" "openai" {
  name                  = local.openai_account_name
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku_name
  custom_subdomain_name = local.openai_subdomain
  tags                  = var.tags
}

resource "azurerm_role_assignment" "openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

resource "azapi_resource" "ai_foundry_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2024-10-01"
  name      = local.ai_project_suffix
  parent_id = azurerm_cognitive_account.openai.id
  location  = var.location

  schema_validation_enabled = false
  body = jsonencode({
    properties = {
      description = "Placeholder AI Foundry project for ${local.base_name}"
    }
  })
}

resource "azapi_resource" "openai_deployment_placeholder" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2024-10-01"
  name      = var.openai_deployment_name
  parent_id = azurerm_cognitive_account.openai.id

  schema_validation_enabled = false
  body = jsonencode({
    sku = {
      name = "Standard"
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
