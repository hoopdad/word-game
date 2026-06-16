module "cosmos" {
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "0.10.0"

  location            = var.spoke_region
  name                = local.cosmos_account
  resource_group_name = azurerm_resource_group.spoke.name

  public_network_access_enabled = false

  consistency_policy = {
    consistency_level = var.cosmos_consistency_level
  }

  geo_locations = [
    {
      location          = var.spoke_region
      failover_priority = 0
      zone_redundant    = false
    }
  ]

  sql_databases = {
    app = {
      name       = var.cosmos_database_name
      throughput = var.cosmos_container_throughput

      containers = {
        events = {
          name                = var.cosmos_container_name
          partition_key_paths = [var.cosmos_partition_key_path]
        }
      }
    }
  }

  private_endpoints = {
    sql = {
      name                          = "pe-cosmos-${local.spoke_prefix}"
      subnet_resource_id            = azurerm_subnet.pep.id
      subresource_name              = "SQL"
      private_dns_zone_group_name   = "default"
      private_dns_zone_resource_ids = [local.hub_private_dns_zone_ids["privatelink.documents.azure.com"]]
    }
  }

  enable_telemetry = false
  tags             = local.common_tags
}
