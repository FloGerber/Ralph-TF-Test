# modules/aadds/main.tf — Azure AD Domain Services module.
# Provisions: optional resource group, AADDS instance with configurable SKU (Standard/Enterprise),
# filtered sync, security settings (TLS 1.2, Kerberos/NTLM password sync), optional hybrid AD
# trust for on-premises connectivity, and null_resource blocks that document GPO configuration
# intent (FSLogix profile registry keys — applied out-of-band via PowerShell/GPMC).

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

# Optional: Resource Group for AADDS — only created when create_resource_group = true.
# Set create_resource_group = false (the default) when the resource group already exists
# or is managed by a higher-level root module (e.g. networking/hub-and-spoke).
resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Azure AD Domain Services (AADDS) Resource
resource "azurerm_active_directory_domain_service" "this" {
  name                = "aadds-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  domain_name           = var.domain_name
  sku                   = var.sku
  filtered_sync_enabled = var.filtered_sync_enabled

  # Network configuration for AADDS — subnet must be snet-aadds with NSG allowing
  # TCP 636 (LDAPS), TCP/UDP 389 (LDAP), TCP/UDP 88 (Kerberos), TCP/UDP 53 (DNS)
  initial_replica_set {
    subnet_id = var.aadds_subnet_id != "" ? var.aadds_subnet_id : var.replica_set_config.subnet_id
  }

  # Security configuration
  security {
    sync_kerberos_passwords = true
    sync_ntlm_passwords     = true
    sync_on_prem_passwords  = var.hybrid_sync_enabled
    ntlm_v1_enabled         = var.ntlm_v1_enabled
    tls_v1_enabled          = !var.tls_1_2_enabled
  }

  tags = var.tags

  depends_on = [
    azurerm_resource_group.this
  ]

  lifecycle {
    ignore_changes = [domain_name]
  }
}

# LDAP/LDAPS Certificate Configuration (for secure LDAP)
resource "azurerm_active_directory_domain_service_trust" "this" {
  count = var.hybrid_sync_enabled ? 1 : 0

  domain_service_id      = azurerm_active_directory_domain_service.this.id
  name                   = "trust-${var.environment}"
  trusted_domain_fqdn    = var.on_premises_sync_config.on_prem_domain
  trusted_domain_dns_ips = split(",", var.on_premises_sync_config.sync_url)
  password               = var.on_premises_sync_config.sync_password

  depends_on = [azurerm_active_directory_domain_service.this]
}

# ---------------------------------------------------------------------------
# Group Policy Objects (GPOs) for FSLogix profile containers
# ---------------------------------------------------------------------------
# NOTE: azurerm_active_directory_domain_service_group_policy does not exist in azurerm 4.x.
# GPO management for AADDS must be performed via PowerShell (GPMC/RSAT) after domain provisioning.
# This null_resource tracks the GPO configuration intent and triggers re-run when it changes.
#
# Required FSLogix registry keys to apply via GPO (Computer Configuration > Preferences > Registry):
#   Key: HKLM\SOFTWARE\FSLogix\Profiles
#     - Enabled                          (DWORD) = 1
#     - VHDLocations                     (MULTI_SZ) = \\<storage>.file.core.windows.net\<share>
#     - DeleteLocalProfileWhenVHDShouldApply (DWORD) = 1
#     - FlipFlopProfileDirectoryName    (DWORD) = 1
#
# Example PowerShell (run on a domain-joined management VM after AADDS is provisioned):
#   Import-Module GroupPolicy
#   $gpoName = "FSLogix-Profile-Container"
#   New-GPO -Name $gpoName -Domain "<domain_name>"
#   $regBase = "HKLM\SOFTWARE\FSLogix\Profiles"
#   Set-GPRegistryValue -Name $gpoName -Key $regBase -ValueName "Enabled"                          -Type DWord      -Value 1
#   Set-GPRegistryValue -Name $gpoName -Key $regBase -ValueName "VHDLocations"                     -Type MultiString -Value "\\<storage>.file.core.windows.net\<share>"
#   Set-GPRegistryValue -Name $gpoName -Key $regBase -ValueName "DeleteLocalProfileWhenVHDShouldApply" -Type DWord  -Value 1
#   Set-GPRegistryValue -Name $gpoName -Key $regBase -ValueName "FlipFlopProfileDirectoryName"    -Type DWord      -Value 1
#   New-GPLink -Name $gpoName -Target "DC=<domain>,DC=local" -Domain "<domain_name>"
#
# Alternatively, deploy FSLogix settings via azurerm_virtual_machine_extension (CustomScript) on
# session hosts, writing the registry keys directly using PowerShell during provisioning.
resource "null_resource" "gpo_config" {
  for_each = { for gpo in var.gpo_config : gpo.name => gpo }

  triggers = {
    name        = each.value.name
    description = each.value.description
    policies    = jsonencode(each.value.policies)
  }

  depends_on = [azurerm_active_directory_domain_service.this]
}

# FSLogix Rule Sets Configuration
# These rules define how FSLogix profiles are redirected and configured per customer/environment
locals {
  fslogix_rule_sets = {
    default_profile = {
      name        = "Default-Profile-Container"
      description = "Default FSLogix profile container rules for all users"
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
        }
      ]
    }
    office_container = {
      name        = "Office-Container"
      description = "FSLogix Office container rules for Microsoft 365 apps"
      rules = [
        {
          include_path = "%username%\\AppData\\Roaming\\Microsoft"
          exclude_path = ""
        }
      ]
    }
  }

  # Merge provided rule sets with defaults
  merged_rule_sets = merge(
    local.fslogix_rule_sets,
    { for rs in var.fslogix_config.rule_sets : rs.name => rs }
  )
}

# FSLogix Configuration Resource (metadata)
# Actual FSLogix configuration is stored in file share and loaded by FSLogix agent
# This creates a configuration document that can be referenced by FSLogix profile management
resource "null_resource" "fslogix_configuration" {
  count = var.fslogix_config.profile_container_enabled ? 1 : 0

  triggers = {
    profile_container_enabled = var.fslogix_config.profile_container_enabled
    office_container_enabled  = var.fslogix_config.office_container_enabled
    profile_share_path        = var.fslogix_config.profile_share_path
    rule_sets                 = jsonencode(local.merged_rule_sets)
  }
}

# Conditional: Directory Sync (Hybrid Identity) Configuration
# Note: Actual sync requires Azure AD Connect or Azure AD Connect Cloud Sync setup
resource "null_resource" "hybrid_sync_marker" {
  count = var.hybrid_sync_enabled ? 1 : 0

  triggers = {
    sync_enabled   = var.on_premises_sync_config.sync_enabled
    on_prem_domain = var.on_premises_sync_config.on_prem_domain
    forest_name    = var.on_premises_sync_config.forest_name
    sync_url       = var.on_premises_sync_config.sync_url
  }
}
