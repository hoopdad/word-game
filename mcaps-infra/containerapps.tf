module "aca_env" {
  source  = "Azure/avm-res-app-managedenvironment/azurerm"
  version = "0.5.0"

  location            = var.spoke_region
  name                = "cae-${local.spoke_prefix}"
  resource_group_name = azurerm_resource_group.spoke.name

  zone_redundant = false

  vnet_configuration = {
    infrastructure_subnet_id = azapi_resource.subnet_aca.id
    internal                 = true
  }

  log_analytics_workspace = {
    resource_id = data.azurerm_log_analytics_workspace.hub.id
  }

  workload_profiles = [
    {
      name                  = "Consumption"
      workload_profile_type = "Consumption"
    }
  ]

  enable_telemetry = false
  tags             = local.common_tags
}

# WAF now runs in the main ACA environment to share the same internal DNS domain.
# This eliminates cross-environment DNS resolution issues.

resource "azurerm_container_app" "web" {
  name                         = "ca-web-${local.spoke_prefix}"
  container_app_environment_id = module.aca_env.resource_id
  resource_group_name          = azurerm_resource_group.spoke.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.common_tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [module.uami.resource_id]
  }

  registry {
    server   = module.acr.resource.login_server
    identity = module.uami.resource_id
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
    external_enabled = true
    target_port      = var.container_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_container_app" "api" {
  name                         = "ca-api-${local.spoke_prefix}"
  container_app_environment_id = module.aca_env.resource_id
  resource_group_name          = azurerm_resource_group.spoke.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.common_tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [module.uami.resource_id]
  }

  registry {
    server   = module.acr.resource.login_server
    identity = module.uami.resource_id
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
    external_enabled = true
    target_port      = var.container_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

resource "azurerm_container_app" "agent" {
  name                         = "ca-agent-${local.spoke_prefix}"
  container_app_environment_id = module.aca_env.resource_id
  resource_group_name          = azurerm_resource_group.spoke.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.common_tags

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [module.uami.resource_id]
  }

  registry {
    server   = module.acr.resource.login_server
    identity = module.uami.resource_id
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

resource "azurerm_container_app" "waf" {
  name                         = "ca-waf-${local.spoke_prefix}"
  container_app_environment_id = module.aca_env.resource_id
  resource_group_name          = azurerm_resource_group.spoke.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.common_tags
  depends_on                   = [azurerm_private_dns_a_record.aca_ext_wildcard]

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "waf"
      image  = var.waf_image
      cpu    = 0.5
      memory = "1.0Gi"

      startup_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"

        initial_delay           = 15
        interval_seconds        = 10
        failure_count_threshold = 5
        timeout                 = 3
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"

        initial_delay           = 15
        interval_seconds        = 10
        failure_count_threshold = 3
        success_count_threshold = 1
        timeout                 = 3
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/healthz"

        initial_delay           = 20
        interval_seconds        = 30
        failure_count_threshold = 3
        timeout                 = 3
      }

      env {
        name  = "WEB_UPSTREAM"
        value = azurerm_container_app.web.ingress[0].fqdn
      }

      env {
        name  = "API_UPSTREAM"
        value = azurerm_container_app.api.ingress[0].fqdn
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
