# environments/dedicated/main.tf — Per-customer dedicated AVD environment root module.
# Independent root configuration with its own backend state key (environments/dedicated).
# Provisions: dedicated spoke networking (modules/networking, enable_firewall=true),
# standard storage for legacy profiles (modules/storage), Log Analytics (modules/monitoring),
# AVD control plane + Personal Flexible VMSS session hosts (modules/avd).
# Additional customers are onboarded by adding module blocks in customer-example.tf.
# Deploy with: tofu init -backend-config=../../backend.hcl && tofu apply
# See docs/runbook-add-customer.md for adding a dedicated customer.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

module "networking" {
  source = "../../modules/networking"

  location            = local.location
  environment         = local.environment
  resource_group_name = local.resource_group_name
  tags                = local.tags

  vnet_config     = local.vnet_config
  nsg_rules       = local.nsg_rules
  enable_firewall = true
}

module "storage" {
  source = "../../modules/storage"

  location            = local.location
  environment         = local.environment
  resource_group_name = local.resource_group_name
  tags                = local.tags

  storage_account_config = local.storage_accounts
  file_shares            = local.file_shares
  vnet_ids               = [module.networking.vnet_id]
}

module "monitoring" {
  source = "../../modules/monitoring"

  location            = local.location
  environment         = local.environment
  resource_group_name = local.resource_group_name
  tags                = local.tags

  log_analytics_workspace_config = local.log_analytics_config
  action_groups                  = local.action_groups
  metric_alerts                  = local.metric_alerts
}

module "avd" {
  source = "../../modules/avd"

  location            = local.location
  environment         = local.environment
  resource_group_name = local.resource_group_name
  tags                = local.tags

  host_pool_config           = local.host_pool_config
  workspace_config           = local.workspace_config
  application_group_config   = local.application_group_config
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
}
