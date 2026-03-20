# modules/dedicated/main.tf — Per-customer dedicated AVD environment composite module.
# Wraps modules/networking, modules/storage, and modules/avd into a single customer-scoped
# deployment unit. Provisions: dedicated VNet + subnets + NSG (optional firewall), Premium
# FileStorage for FSLogix (+ optional App Attach share) with private endpoints, optional
# hub VNet peering, UDR forcing egress via hub firewall, and Flexible VMSS Personal host pool.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  rg_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.customer_name}-dedicated"

  # Default to Premium FileStorage for FSLogix if no storage accounts specified
  storage_account_config = length(var.storage_account_config) > 0 ? var.storage_account_config : [
    {
      name                      = "st${replace(var.customer_name, "-", "")}fslogix"
      account_kind              = "FileStorage"
      account_tier              = "Premium"
      replication_type          = "ZRS"
      enable_https_traffic_only = true
      allow_blob_public_access  = false
      min_tls_version           = "TLS1_2"
      is_hns_enabled            = false
      blob_services             = null
    }
  ]

  # Default file share for FSLogix profiles if none specified.
  # If appattach_quota_gib > 0, also create an appattach share on the same account.
  default_fslogix_account_name = local.storage_account_config[0].name

  default_profile_share = {
    storage_account_name = local.default_fslogix_account_name
    name                 = "profiles"
    quota_gib            = 100
    access_tier          = "Premium"
  }

  appattach_share = var.appattach_quota_gib > 0 ? [{
    storage_account_name = local.default_fslogix_account_name
    name                 = "appattach"
    quota_gib            = var.appattach_quota_gib
    access_tier          = "Premium"
  }] : []

  file_shares = length(var.file_shares) > 0 ? var.file_shares : concat(
    [local.default_profile_share],
    local.appattach_share
  )

  # RBAC assignment for FSLogix SMB Contributor
  fslogix_rbac = var.fslogix_rbac_principal_id != "" ? [{
    name                 = "rbac-fslogix-${var.customer_name}"
    principal_id         = var.fslogix_rbac_principal_id
    role_definition_name = "Storage File Data SMB Share Contributor"
    storage_account_name = local.default_fslogix_account_name
  }] : []

  # Default host pool (Pooled) if none specified
  host_pool_config = length(var.host_pool_config) > 0 ? var.host_pool_config : [
    {
      name               = "hp-${var.customer_name}-pooled"
      friendly_name      = "${var.customer_name} Pooled Desktop Pool"
      description        = "Pooled host pool for ${var.customer_name}"
      type               = "Pooled"
      load_balancer_type = "DepthFirst"
    }
  ]

  # Default workspace if none specified
  workspace_config = length(var.workspace_config) > 0 ? var.workspace_config : [
    {
      name        = "ws-${var.customer_name}"
      description = "Workspace for ${var.customer_name}"
    }
  ]

  # Default application group if none specified
  application_group_config = length(var.application_group_config) > 0 ? var.application_group_config : [
    {
      name           = "ag-${var.customer_name}-desktop"
      host_pool_name = local.host_pool_config[0].name
      workspace_name = "ws-${var.customer_name}"
      type           = "Desktop"
      description    = "Desktop application group for ${var.customer_name}"
    }
  ]

  # Auto-scaling session hosts: min 1, max 4 (scales based on user_count)
  # Estimated: 1 user per 4 vCPU/8GB RAM on Standard_D2s_v3, so scale up as user_count increases
  min_instances = 1
  max_instances = min(4, max(2, (var.user_count + 10) / 15))

  session_host_config = length(var.session_host_config) > 0 ? var.session_host_config : [
    {
      vmss_name                   = "vmss-${var.customer_name}-sh"
      host_pool_name              = local.host_pool_config[0].name
      vm_size                     = "Standard_D2s_v3"
      admin_username              = "AzureAdmin"
      instance_count              = local.min_instances
      custom_image_id             = var.avd_image_id
      subnet_id                   = module.networking.subnet_ids["dedicated-avd"]
      os_disk_size_gb             = 128
      enable_automatic_os_upgrade = true
      zones                       = ["1", "2", "3"]
      tags                        = {}
    }
  ]

  # Determine the subnet key for private endpoints; fall back to "dedicated-app" if
  # the caller's vnet_config does not include "snet-dedicated-storage".
  pe_subnet_key = var.private_endpoint_subnet_name

  # Build peering config only when hub_vnet_id is provided
  peering_config = var.hub_vnet_id != "" ? {
    remote_vnet_id          = var.hub_vnet_id
    remote_vnet_name        = var.hub_vnet_name
    allow_forwarded_traffic = true
    allow_gateway_transit   = false
  } : null
}

module "networking" {
  source = "../networking"

  location            = var.location
  environment         = "dedicated-${var.customer_name}"
  resource_group_name = local.rg_name
  tags                = var.tags

  vnet_config     = var.vnet_config
  nsg_rules       = var.nsg_rules
  enable_firewall = false

  # Inject AADDS DNS server IPs so session hosts resolve the domain
  dns_servers = var.aadds_dns_servers

  # Hub-spoke VNet peering (optional — only when hub_vnet_id is provided)
  enable_peering = var.hub_vnet_id != ""
  peering_config = local.peering_config
}

# ---------------------------------------------------------------------------
# Route table: force all spoke egress through hub firewall
# Created only when hub_firewall_private_ip is provided.
# ---------------------------------------------------------------------------
resource "azurerm_route_table" "spoke_to_hub" {
  count = var.hub_firewall_private_ip != "" ? 1 : 0

  name                          = "rt-${var.customer_name}-spoke-to-hub"
  location                      = var.location
  resource_group_name           = module.networking.resource_group_name
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.hub_firewall_private_ip
  }

  tags = var.tags
}

# Associate the route table with all subnets in the spoke VNet
resource "azurerm_subnet_route_table_association" "spoke_to_hub" {
  for_each = var.hub_firewall_private_ip != "" ? module.networking.subnet_ids : {}

  subnet_id      = each.value
  route_table_id = azurerm_route_table.spoke_to_hub[0].id
}

module "storage" {
  source = "../storage"

  location            = var.location
  environment         = "dedicated-${var.customer_name}"
  resource_group_name = local.rg_name
  tags                = var.tags

  storage_account_config = local.storage_account_config
  file_shares            = local.file_shares
  rbac_assignments       = local.fslogix_rbac

  # Network rules default to Deny when private endpoints are configured.
  vnet_ids = []

  private_endpoint_config = var.enable_private_endpoints ? [
    for sa in local.storage_account_config : {
      name                 = sa.name
      storage_account_name = sa.name
      subnet_id            = module.networking.subnet_ids[local.pe_subnet_key]
      private_dns_zone_id  = var.private_dns_zone_file_id
    }
  ] : []
}

module "avd" {
  source = "../avd"

  location            = var.location
  environment         = "dedicated-${var.customer_name}"
  resource_group_name = local.rg_name
  tags                = var.tags

  host_pool_config         = local.host_pool_config
  workspace_config         = local.workspace_config
  application_group_config = local.application_group_config
  session_host_config      = local.session_host_config

  # Pass-through AADDS domain join configuration to session host VMSS extensions
  domain_join_config = var.domain_join_config

  # Pass-through FSLogix profile container configuration
  fslogix_config = var.fslogix_config

  app_attach_type            = var.app_attach_type
  app_attach_packages        = var.app_attach_packages
  log_analytics_workspace_id = var.log_analytics_workspace_id
}
