terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  subscription_id = var.spoke_subscription_id
}

provider "azurerm" {
  alias = "hub"
  features {}
  subscription_id = var.hub_subscription_id
}

provider "azapi" {
  subscription_id = var.spoke_subscription_id
}
