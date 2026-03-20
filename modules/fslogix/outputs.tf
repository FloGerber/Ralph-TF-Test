# modules/fslogix/outputs.tf — Outputs from the FSLogix storage module.

output "storage_account_ids" {
  description = "IDs of the FSLogix storage accounts"
  value = {
    for name, account in azurerm_storage_account.fslogix :
    name => account.id
  }
}

output "storage_account_names" {
  description = "Names of the FSLogix storage accounts"
  value = {
    for name, account in azurerm_storage_account.fslogix :
    name => account.name
  }
}

output "profile_container_endpoints" {
  description = "File share endpoints for profile containers"
  value = {
    for share_key, share in azurerm_storage_share.profile_container :
    share_key => {
      share_id  = share.id
      share_url = "${azurerm_storage_account.fslogix[split("-", share_key)[0]].primary_file_host}/${share.name}"
      name      = share.name
    }
  }
}

output "office_container_endpoints" {
  description = "File share endpoints for Office containers (if enabled)"
  value = {
    for share_key, share in azurerm_storage_share.office_container :
    share_key => {
      share_id  = share.id
      share_url = "${azurerm_storage_account.fslogix[split("-", share_key)[0]].primary_file_host}/${share.name}"
      name      = share.name
    }
  }
}

output "private_endpoint_ids" {
  description = "IDs of the private endpoints for storage accounts"
  value = {
    for name, endpoint in azurerm_private_endpoint.fslogix_storage :
    name => endpoint.id
  }
}

output "fslogix_configuration" {
  description = "FSLogix configuration including rule sets and container settings"
  value = {
    profile_containers_enabled = length(var.profile_share_configs) > 0
    office_containers_enabled  = var.office_container_enabled
    premium_storage_enabled    = var.enable_premium_storage
    rule_sets = {
      for rule_set in local.all_rule_sets :
      rule_set.name => {
        description = rule_set.description
        rules       = rule_set.rules
      }
    }
    vcpu_quota_per_container = var.profile_container_vcpu_quota
    max_users_per_container  = var.profile_container_max_users
  }
}

output "fslogix_mount_paths" {
  description = "Mount paths for FSLogix profile containers"
  value = {
    profile_containers = {
      for share_key, share in azurerm_storage_share.profile_container :
      share.name => {
        mount_path      = "${azurerm_storage_account.fslogix[split("-", share_key)[0]].primary_file_host}/${share.name}"
        storage_account = split("-", share_key)[0]
        quota_gb        = share.quota
        access_tier     = share.access_tier
      }
    }
    office_containers = var.office_container_enabled ? {
      for share_key, share in azurerm_storage_share.office_container :
      share.name => {
        mount_path      = "${azurerm_storage_account.fslogix[split("-", share_key)[0]].primary_file_host}/${share.name}"
        storage_account = split("-", share_key)[0]
        quota_gb        = share.quota
        access_tier     = share.access_tier
      }
    } : {}
  }
}

output "rule_sets_configuration" {
  description = "FSLogix rule sets for profile redirection and inclusion/exclusion"
  value = {
    for rule_set in local.all_rule_sets :
    rule_set.name => {
      name        = rule_set.name
      description = rule_set.description
      rules = [
        for rule in rule_set.rules : {
          include_path = rule.include_path
          exclude_path = rule.exclude_path != "" ? rule.exclude_path : null
        }
      ]
    }
  }
}

output "storage_tier_info" {
  description = "Information about storage tier and redundancy"
  value = {
    tier                  = var.enable_premium_storage ? "Premium" : "Standard"
    replication_type      = local.replication_type
    geo_redundant_enabled = var.enable_geo_redundant
    file_storage_accounts = length(azurerm_storage_account.fslogix)
  }
}

output "recommended_nsg_rules" {
  description = "Recommended NSG rules for FSLogix storage access"
  value = [
    {
      name                       = "Allow-SMB-FileShare"
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "445"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "Storage"
      description                = "Allow SMB protocol for file share access"
    },
    {
      name                       = "Allow-HTTPS-Storage"
      priority                   = 101
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "Storage"
      description                = "Allow HTTPS for storage connectivity"
    }
  ]
}

output "fslogix_integration_config" {
  description = "Complete FSLogix configuration for integration with AADDS and AVD"
  value = {
    storage_accounts = {
      for name, account in azurerm_storage_account.fslogix :
      name => {
        id          = account.id
        name        = account.name
        tier        = account.account_tier
        kind        = account.account_kind
        replication = account.account_replication_type
      }
    }
    profile_shares = [
      for share_key, share in azurerm_storage_share.profile_container : {
        mount_path             = "${azurerm_storage_account.fslogix[split("-", share_key)[0]].primary_file_host}/${share.name}"
        share_name             = share.name
        quota_gb               = share.quota
        access_tier            = share.access_tier
        recommended_vcpu_limit = var.profile_container_vcpu_quota
      }
    ]
    office_shares = var.office_container_enabled ? [
      for share_key, share in azurerm_storage_share.office_container : {
        mount_path = "${azurerm_storage_account.fslogix[split("-", share_key)[0]].primary_file_host}/${share.name}"
        share_name = share.name
        quota_gb   = share.quota
      }
    ] : []
    rule_sets               = local.all_rule_sets
    premium_storage_enabled = var.enable_premium_storage
  }
}
