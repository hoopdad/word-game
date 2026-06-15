terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.50"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.spoke_subscription_id
}

provider "azurerm" {
  alias = "hub"
  features {}
  subscription_id = var.hub_subscription_id
}
