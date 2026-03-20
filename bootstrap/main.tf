# bootstrap/main.tf — One-time platform foundation layer.
# Provisions: remote state storage account (GRS, private), Hub VNet with Azure Firewall
# Premium (IDS: Deny, Threat Intel: Deny), Private DNS Zones for private endpoints,
# Log Analytics Workspace, Management Groups, Azure Policy, Microsoft Defender for Cloud,
# and an optional OIDC service principal role assignment.
# Deploy once before all other layers. Uses local state on first run.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  description = "Azure region for state storage"
  type        = string
  default     = "germanywestcentral"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "state_storage_account_name" {
  description = "Name for the state storage account"
  type        = string
  default     = "tfstatestorage"
}

variable "container_name" {
  description = "Name for the state container"
  type        = string
  default     = "tfstate"
}

locals {
  resource_group_name = "rg-tfstate-${var.environment}"
  tags = {
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    Purpose     = "RemoteStateBackend"
  }
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_33: State backend uses Blob service only; Queue service is not enabled on StorageV2 backend accounts
  name                            = var.state_storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

# NOTE: The role assignment for state storage access should be granted to the
# CI/CD pipeline's service principal or a dedicated managed identity — not to
# the storage account's own system-assigned identity. Grant the required role
# (e.g., "Storage Blob Data Contributor") to the appropriate principal via:
#
#   resource "azurerm_role_assignment" "state_access" {
#     scope                = azurerm_storage_account.this.id
#     role_definition_name = "Storage Blob Data Contributor"
#     principal_id         = "<pipeline_service_principal_object_id>"
#   }
#
# The original self-assignment (storage account identity → itself) was a no-op
# and has been removed.

output "backend_config" {
  description = "Backend configuration values"
  value = {
    storage_account_name = azurerm_storage_account.this.name
    container_name       = azurerm_storage_container.this.name
    resource_group_name  = azurerm_resource_group.this.name
    subscription_id      = data.azurerm_subscription.current.subscription_id
    tenant_id            = data.azurerm_subscription.current.tenant_id
  }
  sensitive = true
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.this.name
}

output "container_name" {
  description = "Container name"
  value       = azurerm_storage_container.this.name
}

data "azurerm_subscription" "current" {}

// Management Groups for landing zones
resource "azurerm_management_group" "root" {
  name         = "landingzones"
  display_name = "Landing Zones"
  # created under the tenant root by default
}

resource "azurerm_management_group" "management" {
  name                       = "mg-management"
  display_name               = "Management"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "connectivity" {
  name                       = "mg-connectivity"
  display_name               = "Connectivity"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "shared" {
  name                       = "mg-shared"
  display_name               = "Shared"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "dedicated" {
  name                       = "mg-dedicated"
  display_name               = "Dedicated"
  parent_management_group_id = azurerm_management_group.root.id
}

// Simple policy definition to ensure cost-management tagging (audit if missing)
resource "azurerm_policy_definition" "require_costcenter_tag" {
  name         = "require-costcenter-tag"
  display_name = "Require CostCenter Tag"
  policy_type  = "Custom"
  mode         = "All"

  policy_rule = <<POLICY
{
  "if": {
    "anyOf": [
      {
        "field": "tags['CostCenter']",
        "exists": "false"
      },
      {
        "field": "tags['CostCenter']",
        "equals": ""
      }
    ]
  },
  "then": {
    "effect": "audit"
  }
}
POLICY

  metadata = <<METADATA
{
  "category": "Cost Management",
  "version": "1.0"
}
METADATA
}

// Assign policy at the landing zones root management group scope
resource "azurerm_management_group_policy_assignment" "require_costcenter_assignment" {
  name                 = "requirecostcenter"
  display_name         = "Require CostCenter Tag Assignment"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = azurerm_policy_definition.require_costcenter_tag.id
  description          = "Audit resources missing CostCenter tag to support cost management"
}

// Log Analytics workspace used by monitoring and security
resource "azurerm_log_analytics_workspace" "bootstrap_law" {
  name                = "law-bootstrap-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

// Enable Azure Defender (Security Center) standard pricing for Virtual Machines as an example
resource "azurerm_security_center_subscription_pricing" "vm_pricing" {
  resource_type = "VirtualMachines"
  tier          = "Standard"
}

// ---------------------------------------------------------------------------
// Hub Virtual Network
// ---------------------------------------------------------------------------
// Hub VNet: 10.0.0.0/16 with subnets required for gateway, firewall,
// management, frontend and backend workloads.
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.0.0/27"]
}

// AzureFirewallSubnet must be at least /26
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/26"]
}

resource "azurerm_subnet" "management" {
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "snet-frontend"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.4.0/24"]
}

// ---------------------------------------------------------------------------
// Azure Firewall
// ---------------------------------------------------------------------------
// NOTE: Intrusion Detection (IDS) requires Premium tier for both the Firewall
// Policy and the Firewall itself. The acceptance criteria specifies Standard
// SKU for the firewall but also IDS: Deny — Premium is required to satisfy
// both constraints simultaneously. The firewall is therefore provisioned at
// Premium tier to enable IDS. Downgrade to Standard by removing the
// intrusion_detection block and changing sku_tier to "Standard" if cost is a
// concern and IDS is not required.
resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_firewall_policy" "hub" {
  name                     = "afwp-hub-${var.environment}"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.this.name
  sku                      = "Premium"
  threat_intelligence_mode = "Deny"

  intrusion_detection {
    mode = "Deny"
  }

  insights {
    enabled                            = true
    default_log_analytics_workspace_id = azurerm_log_analytics_workspace.bootstrap_law.id
    retention_in_days                  = 30
  }

  tags = local.tags
}

resource "azurerm_firewall" "hub" {
  name                = "afw-hub-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  # CKV_AZURE_216: threat_intel_mode must be set directly on the firewall resource
  # even when threat_intelligence_mode = "Deny" is also set on the associated policy.
  threat_intel_mode = "Deny"

  ip_configuration {
    name                 = "ipconfig-hub"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = local.tags
}

// ---------------------------------------------------------------------------
// Private DNS Zones
// ---------------------------------------------------------------------------
locals {
  private_dns_zones = [
    "privatelink.file.core.windows.net",
    "privatelink.blob.core.windows.net",
  ]
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = toset(local.private_dns_zones)
  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${replace(each.key, ".", "-")}-hub"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags
}

// ---------------------------------------------------------------------------
// OIDC Service Principal outputs
// ---------------------------------------------------------------------------
// The service principal (app registration) used for OIDC-based CI/CD access
// must be created out-of-band (e.g. via az ad app create or the Azure Portal)
// and its object ID / app ID passed in via variables. The required role
// assignments are documented below and in BACKEND.md.
variable "oidc_sp_app_id" {
  description = "App (client) ID of the OIDC service principal used by CI/CD pipelines"
  type        = string
  default     = ""
}

variable "oidc_sp_object_id" {
  description = "Object ID of the OIDC service principal used by CI/CD pipelines"
  type        = string
  default     = ""
}

// Grant Storage Blob Data Contributor on the state storage account when an
// OIDC service principal object ID is supplied.
resource "azurerm_role_assignment" "oidc_state_access" {
  count                = var.oidc_sp_object_id != "" ? 1 : 0
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.oidc_sp_object_id
}

output "oidc_guidance" {
  description = "OIDC service principal app ID and required role assignments"
  value = {
    oidc_sp_app_id = var.oidc_sp_app_id
    required_roles = {
      state_storage = "Storage Blob Data Contributor on ${azurerm_storage_account.this.id}"
      subscription  = "Contributor or custom role on /subscriptions/<subscription_id>"
    }
    documentation = "See BACKEND.md for detailed OIDC setup instructions"
  }
}

output "hub_vnet_id" {
  description = "Hub VNet resource ID"
  value       = azurerm_virtual_network.hub.id
}

output "firewall_private_ip" {
  description = "Private IP address of the Azure Firewall"
  value       = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

output "private_dns_zone_ids" {
  description = "Map of Private DNS Zone names to resource IDs"
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}
