# environments/shared/main.tf — Shared multi-tenant AVD environment root module.
# Independent root configuration with its own backend state key (environments/shared).
# Provisions: shared spoke networking (modules/networking), AADDS (modules/aadds),
# per-customer FSLogix Premium File Shares (modules/storage), Log Analytics (modules/monitoring),
# AVD control plane + Pooled Flexible VMSS session hosts (modules/avd),
# Azure Image Builder golden image pipeline (imaging/image-builder),
# customer resource groups and RBAC (modules/customer).
# Deploy with: tofu init -backend-config=../../backend.hcl && tofu apply
# See WORKSPACES.md for two-pass AADDS deployment instructions.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {
  use_msi = true
}

data "azurerm_client_config" "current" {}

module "networking" {
  source = "../../modules/networking"

  location            = local.location
  environment         = local.environment
  resource_group_name = local.resource_group_name
  tags                = local.tags

  vnet_config     = local.vnet_config
  nsg_rules       = local.nsg_rules
  enable_firewall = false
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

# ---------------------------------------------------------------------------
# Per-customer Premium FileStorage accounts (FSLogix profiles) + App Attach
# ---------------------------------------------------------------------------
# Each customer gets an isolated Premium FileStorage account with a "profiles"
# share (100 GiB minimum). A single shared "appattach" account holds MSIX/
# App Attach packages for the shared host pool.
module "premium_storage" {
  source = "../../modules/storage"

  location            = local.location
  environment         = local.environment
  resource_group_name = local.resource_group_name
  tags                = local.tags

  storage_account_config  = local.premium_storage_accounts
  file_shares             = local.premium_file_shares
  private_endpoint_config = local.premium_storage_private_endpoints
  rbac_assignments        = local.fslogix_rbac_assignments

  # Network rules default to Deny when private_endpoint_config is populated.
  # The storage module derives this automatically from the config list length.
  vnet_ids = []
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
  scaling_plan_config        = local.scaling_plan_config
  lob_application_config     = local.lob_application_config
  app_attach_type            = "AppAttach"
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  # Example AVD session host and network interface configuration for the shared host pool
  # These are example/demo objects to allow `tofu validate`/`tofu plan` to reference
  # the subsystem wiring. In production these should be provided per-customer via
  # higher-level orchestration modules that create customer-specific resource groups.
  virtual_machine_config = [
    {
      name            = "vm-shared-1"
      host_pool_name  = "hp-shared-pool"
      vm_size         = "Standard_DS2_v2"
      admin_username  = "avdadmin"
      admin_password  = "P@ssw0rd123!"
      image_id        = ""
      custom_image_id = ""
      subnet_id       = module.networking.subnet_ids["shared-avd"]
      disk_type       = "StandardSSD_LRS"
      os_disk_size_gb = 128
      tags            = {}
    }
  ]

  network_interface_config = [
    {
      name                          = "nic-vm-shared-1"
      vm_name                       = "vm-shared-1"
      subnet_id                     = module.networking.subnet_ids["shared-avd"]
      ip_forwarding_enabled         = false
      enable_accelerated_networking = true
      private_ip_address_allocation = "Dynamic"
      dns_servers                   = []
    }
  ]

  # Example session host scale set configuration (maps to Flexible VMSS in modules/avd)
  session_host_config = local.session_host_config
}

resource "azurerm_role_assignment" "shared_appattach_session_hosts" {
  for_each = module.avd.session_host_identity_principal_ids

  scope                = module.premium_storage.storage_account_ids[local.appattach_storage_account.name]
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = each.value
}

module "aadds" {
  source = "../../modules/aadds"

  location            = local.location
  environment         = local.environment
  resource_group_name = "rg-avd-shared-aadds"
  tags                = local.tags

  domain_name           = local.aadds_config.domain_name
  sku                   = local.aadds_config.sku
  filtered_sync_enabled = local.aadds_config.filtered_sync_enabled
  ntlm_v1_enabled       = local.aadds_config.ntlm_v1_enabled
  tls_1_2_enabled       = local.aadds_config.tls_1_2_enabled
  hybrid_sync_enabled   = local.aadds_config.hybrid_sync_enabled
  replica_set_config    = local.aadds_replica_set_config

  # FSLogix configuration for AADDS-managed profiles
  fslogix_config = {
    profile_container_enabled = true
    office_container_enabled  = true
    profile_share_path        = "\\\\stsharedfslogix.file.core.windows.net\\profiles"
    rule_sets                 = local.fslogix_rule_sets
  }

  # GPO configurations for security baselines
  gpo_config = []
}

module "fslogix" {
  source = "../../modules/fslogix"

  location            = local.location
  environment         = local.environment
  resource_group_name = "rg-avd-shared-fslogix"
  tags                = local.tags

  storage_account_configs  = local.fslogix_config.storage_account_configs
  profile_share_configs    = local.fslogix_config.profile_share_configs
  office_container_enabled = local.fslogix_config.office_container_enabled
  office_share_configs     = local.fslogix_config.office_share_configs
  rule_sets                = local.fslogix_rule_sets

  # Optional: place storage endpoints in FSLogix storage subnet if available
  subnet_id                    = local.fslogix_config.enable_private_endpoints ? module.networking.subnet_ids["shared-app"] : ""
  enable_private_endpoints     = local.fslogix_config.enable_private_endpoints
  enable_premium_storage       = local.fslogix_config.enable_premium_storage
  enable_geo_redundant         = local.fslogix_config.enable_geo_redundant
  profile_container_vcpu_quota = local.fslogix_config.profile_container_vcpu_quota
  profile_container_max_users  = local.fslogix_config.profile_container_max_users
}

module "image_builder" {
  source = "../../imaging/image-builder"

  location               = local.location
  environment            = local.image_builder_config.environment
  resource_group_name    = local.image_builder_config.resource_group_name
  tags                   = local.tags
  create_shared_gallery  = local.image_builder_config.create_shared_gallery
  create_staging_storage = local.image_builder_config.create_staging_storage
  replication_regions    = local.image_builder_config.replication_regions
  image_publisher        = local.image_builder_config.image_publisher
  image_offer            = local.image_builder_config.image_offer
  image_sku              = local.image_builder_config.image_sku
}
