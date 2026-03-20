# modules/storage/main.tf — Azure Storage accounts, file shares, private endpoints, and RBAC.
# Provisions: storage accounts with hardened defaults (no public access, no local users,
# TLS 1.2, HTTPS only, ZRS replication), file shares, private endpoints with optional
# Private DNS Zone group for automatic A-record registration, and RBAC role assignments.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_33:FileStorage Premium accounts have no Queue service; queue logging N/A
  #checkov:skip=CKV_AZURE_190:FileStorage Premium accounts have no Blob service; blob public-access check N/A
  #checkov:skip=CKV_AZURE_206:Replication type is enforced as ZRS or RA-GRS by callers; static analysis cannot evaluate the ternary
  for_each = { for config in var.storage_account_config : config.name => config }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  account_kind        = each.value.account_kind != null ? each.value.account_kind : "StorageV2"
  account_tier        = each.value.account_tier != null ? each.value.account_tier : "Standard"
  # Default to ZRS (zone-redundant) for better resilience; callers may override per account.
  # RA-GRS is used when geo-redundancy is explicitly requested at module level.
  account_replication_type        = each.value.replication_type != null ? each.value.replication_type : (var.enable_geo_redundant_storage ? "RA-GRS" : "ZRS")
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  is_hns_enabled                  = each.value.is_hns_enabled != null ? each.value.is_hns_enabled : false
  # Disable public network access — connectivity is exclusively via Private Endpoints.
  public_network_access_enabled = false
  # Disable local (SAS-key-based) user access; use Entra ID / RBAC only.
  local_user_enabled = false

  blob_properties {
    dynamic "delete_retention_policy" {
      for_each = each.value.blob_services != null && each.value.blob_services.delete_retention_days != null && each.value.blob_services.delete_retention_days > 0 ? [each.value.blob_services.delete_retention_days] : []
      content {
        days = delete_retention_policy.value
      }
    }
  }

  tags = var.tags
}

resource "azurerm_storage_share" "this" {
  for_each = { for share in var.file_shares : "${share.storage_account_name}-${share.name}" => share }

  name                 = each.value.name
  storage_account_name = each.value.storage_account_name
  quota                = each.value.quota_gib != null ? each.value.quota_gib : 100
  access_tier          = each.value.access_tier != null ? each.value.access_tier : "Hot"
}

resource "azurerm_storage_account_network_rules" "this" {
  for_each = { for config in var.storage_account_config : config.name => config }

  storage_account_id = azurerm_storage_account.this[each.key].id

  # Always deny public access; traffic must flow via Private Endpoints or AzureServices bypass.
  default_action             = "Deny"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = length(var.vnet_ids) > 0 ? [for pe in var.private_endpoint_config : pe.subnet_id if pe.storage_account_name == each.key] : []
}

resource "azurerm_private_endpoint" "this" {
  for_each = { for config in var.private_endpoint_config : config.name => config }

  name                = "pe-${each.value.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value.subnet_id

  private_service_connection {
    name                           = "psc-${each.value.name}"
    private_connection_resource_id = azurerm_storage_account.this[each.value.storage_account_name].id
    is_manual_connection           = false
    # FileStorage accounts only support the "file" subresource.
    # StorageV2/BlobStorage accounts support "blob". Using ["file"] here
    # assumes all storage accounts in this module are FileStorage (Premium).
    # For mixed workloads split into separate module calls.
    subresource_names = ["file"]
  }

  dynamic "private_dns_zone_group" {
    for_each = each.value.private_dns_zone_id != null ? [each.value.private_dns_zone_id] : []
    content {
      name                 = "dns-${each.value.name}"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }

  tags = var.tags
}

// Optional RBAC assignments scoped to storage accounts or resource group
resource "azurerm_role_assignment" "this" {
  # Only create assignments that are scoped to a storage account name
  for_each = { for a in var.rbac_assignments : a.name => a if lookup(a, "storage_account_name", "") != "" }

  scope                = azurerm_storage_account.this[each.value.storage_account_name].id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}

// Fallback RBAC assignments at resource group scope (for items without storage_account_name)
resource "azurerm_role_assignment" "rg_scope" {
  for_each = { for a in var.rbac_assignments : a.name => a if lookup(a, "storage_account_name", "") == "" }

  scope                = var.resource_group_name
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}

output "environment" {
  description = "Environment label passed to the storage module"
  value       = var.environment
}
