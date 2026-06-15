resource "azurerm_container_app_environment" "aca_env" {
  name                           = "cae-${local.base_name}"
  location                       = var.location
  resource_group_name            = azurerm_resource_group.rg.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.aca_logs.id
  infrastructure_subnet_id       = azurerm_subnet.aca.id
  internal_load_balancer_enabled = true
  tags                           = var.tags
}

resource "azurerm_container_app_environment" "waf_env" {
  name                       = local.waf_env_name
  location                   = var.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aca_logs.id
  infrastructure_subnet_id   = azurerm_subnet.waf.id
  # This is the single approved public ingress edge.
  internal_load_balancer_enabled = false
  public_network_access          = "Enabled"
  tags                           = var.tags
}

resource "azurerm_container_app" "waf" {
  name                         = local.waf_name
  container_app_environment_id = azurerm_container_app_environment.waf_env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"
  tags                         = var.tags
  depends_on                   = [azurerm_private_dns_a_record.aca_internal_wildcard]

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
    target_port      = 80

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
