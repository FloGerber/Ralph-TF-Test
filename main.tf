# Root configuration — provider and backend setup.
# This file sets the azurerm provider configuration and the Azure Blob Storage remote
# backend. Environment layers (environments/shared, environments/dedicated) are independent
# root modules deployed separately — see WORKSPACES.md.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "tfstatestorage"
    container_name       = "tfstate"
    key                  = "env-${terraform.workspace}"
    use_oidc             = true
  }
}

provider "azurerm" {
  features {}
}

# NOTE: environments/shared and environments/dedicated are root configurations
# with their own backends and cannot be called as child modules from here.
# Deploy each layer independently — see WORKSPACES.md for the layered deployment
# order and workspace instructions.
