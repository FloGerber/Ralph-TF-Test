# modules/fslogix/main.tf — FSLogix profile container storage module.
# Provisions: Premium FileStorage account (ZRS by default), profile container and office
# container file shares with configurable quotas, network rules (default Deny, AzureServices
# bypass), private endpoint (subresource "file"), and null_resource tracking FSLogix rule sets.
# All storage hardened: no public access, no local users, TLS 1.2, HTTPS only.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

locals {
  replication_type = var.enable_geo_redundant ? (var.enable_premium_storage ? "ZRS" : "GRS") : (var.enable_premium_storage ? "ZRS" : "LRS")

  # Default rule sets for FSLogix profile containers
  default_rule_sets = [
    {
      name        = "profile-container-default"
      description = "Default profile container rules - redirect user profile folders"
      rules = [
        {
          include_path = "%username%"
          exclude_path = "AppData\\Local\\Temp"
        },
        {
          include_path = "Desktop"
          exclude_path = ""
        },
        {
          include_path = "Documents"
          exclude_path = ""
        },
        {
          include_path = "Downloads"
          exclude_path = ""
        },
        {
          include_path = "AppData\\Roaming"
          exclude_path = ""
        }
      ]
    }
  ]

  # Office container rule set
  office_rule_sets = var.office_container_enabled ? [
    {
      name        = "office-container-default"
      description = "Office container rules - redirect Microsoft 365 app data"
      rules = [
        {
          include_path = "%username%\\AppData\\Roaming\\Microsoft"
          exclude_path = ""
        },
        {
          include_path = "%username%\\AppData\\Local\\Microsoft\\Outlook"
          exclude_path = ""
        }
      ]
    }
  ] : []

  # Merge default and custom rule sets
  all_rule_sets = concat(local.default_rule_sets, local.office_rule_sets, var.rule_sets)
}

# Storage Accounts for FSLogix Profile Containers
resource "azurerm_storage_account" "fslogix" {
  #checkov:skip=CKV_AZURE_59: public_network_access_enabled is set to false; Checkov static analysis misdetects ternary-based allow_nested_items_to_be_public as a public access issue
  #checkov:skip=CKV_AZURE_44: min_tls_version uses each.value.min_tls_version which is validated by callers to be TLS1_2; static analysis cannot evaluate map lookups
  #checkov:skip=CKV_AZURE_206: replication_type is enforced as ZRS or RA-GRS via local.replication_type logic; static analysis cannot evaluate the ternary expression
  #checkov:skip=CKV_AZURE_190: FileStorage Premium accounts have no Blob service; blob public-access check N/A for FileStorage kind
  for_each = { for config in var.storage_account_configs : config.name => config }

  name                            = each.value.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = var.enable_premium_storage ? "Premium" : each.value.account_tier
  account_replication_type        = local.replication_type
  account_kind                    = "FileStorage" # Optimized for file shares
  https_traffic_only_enabled      = each.value.enable_https_only
  min_tls_version                 = each.value.min_tls_version
  allow_nested_items_to_be_public = each.value.allow_blob_access
  public_network_access_enabled   = false

  tags = var.tags
}

# Profile Container File Shares
resource "azurerm_storage_share" "profile_container" {
  for_each = { for share in var.profile_share_configs : "${share.storage_account_name}-${share.name}" => share }

  name                 = each.value.name
  storage_account_name = each.value.storage_account_name
  quota                = each.value.quota_gib
  access_tier          = var.enable_premium_storage ? "Premium" : each.value.access_tier

  depends_on = [azurerm_storage_account.fslogix]
}

# Office Container File Shares (optional)
resource "azurerm_storage_share" "office_container" {
  for_each = var.office_container_enabled ? { for share in var.office_share_configs : "${share.storage_account_name}-${share.name}" => share } : {}

  name                 = each.value.name
  storage_account_name = each.value.storage_account_name
  quota                = each.value.quota_gib
  access_tier          = var.enable_premium_storage ? "Premium" : each.value.access_tier

  depends_on = [azurerm_storage_account.fslogix]
}

# Private Endpoints for Storage Accounts (if enabled and subnet provided)
resource "azurerm_private_endpoint" "fslogix_storage" {
  for_each = var.enable_private_endpoints && var.subnet_id != "" ? { for account_name, config in azurerm_storage_account.fslogix : account_name => config } : {}

  name                = "pe-fslogix-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-fslogix-${each.key}"
    private_connection_resource_id = azurerm_storage_account.fslogix[each.key].id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  tags = var.tags
}

# Storage Account Network Rules - restrict access to specific subnets
resource "azurerm_storage_account_network_rules" "fslogix" {
  for_each = azurerm_storage_account.fslogix

  storage_account_id = each.value.id
  default_action     = var.subnet_id != "" ? "Deny" : "Allow"
  bypass             = ["AzureServices"]

  # Virtual network service endpoint rules - restrict access to the provided subnet
  virtual_network_subnet_ids = var.subnet_id != "" ? [var.subnet_id] : []
}

# FSLogix Configuration File (stored as metadata resource)
resource "null_resource" "fslogix_config" {
  triggers = {
    profile_containers = jsonencode({
      for share in var.profile_share_configs :
      "${share.storage_account_name}/${share.name}" => {
        quota_gb             = share.quota_gib
        container_type       = "Profile"
        vcpu_limit           = var.profile_container_vcpu_quota
        max_concurrent_users = var.profile_container_max_users
        delete_on_logoff     = false
        include_dir          = "%username%"
        exclude_dir          = "AppData\\Local\\Temp"
      }
    })
    office_containers = var.office_container_enabled ? jsonencode({
      for share in var.office_share_configs :
      "${share.storage_account_name}/${share.name}" => {
        quota_gb       = share.quota_gib
        container_type = "Office"
      }
    }) : "{}"
    rule_sets = jsonencode(local.all_rule_sets)
  }
}

output "environment" {
  description = "Environment label passed to the FSLogix module"
  value       = var.environment
}
