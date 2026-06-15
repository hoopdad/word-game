data "azurerm_log_analytics_workspace" "hub" {
  provider            = azurerm.hub
  name                = var.hub_law_name
  resource_group_name = var.hub_resource_group_name
}

locals {
  hub_law_id   = data.azurerm_log_analytics_workspace.hub.id
  hub_ampls_id = "/subscriptions/${var.hub_subscription_id}/resourceGroups/${var.hub_resource_group_name}/providers/Microsoft.Insights/privateLinkScopes/${var.hub_ampls_name}"
}
