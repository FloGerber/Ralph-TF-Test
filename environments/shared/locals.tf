# environments/shared/locals.tf — Local values for the shared AVD environment.
# Contains all configuration: VNet/subnet definitions, storage account configs,
# AVD host pool / workspace / app group / scaling plan, FSLogix, AADDS, monitoring,
# and customer factories. Edit here to change environment topology.

locals {
  environment         = "shared"
  location            = "eastus"
  resource_group_name = "rg-avd-shared"

  tags = {
    Environment = "Production"
    Project     = "AVD"
    ManagedBy   = "OpenTofu"
    HostingType = "Shared"
  }

  vnet_config = {
    address_spaces = ["10.1.0.0/16"]
    subnets = [
      {
        name              = "shared-app"
        address_prefixes  = ["10.1.1.0/24"]
        service_endpoints = ["Microsoft.Storage"]
        delegations       = []
      },
      {
        name              = "shared-avd"
        address_prefixes  = ["10.1.2.0/24"]
        service_endpoints = ["Microsoft.Storage"]
        delegations       = ["Microsoft.WindowsVirtualDesktop/hostPools"]
      },
      {
        name              = "AzureBastionSubnet"
        address_prefixes  = ["10.1.3.0/24"]
        service_endpoints = []
        delegations       = []
      },
      {
        # Dedicated subnet for storage private endpoints (FSLogix + App Attach)
        name              = "snet-shared-storage"
        address_prefixes  = ["10.1.4.0/24"]
        service_endpoints = ["Microsoft.Storage"]
        delegations       = []
      }
    ]
  }

  nsg_rules = [
    {
      name                       = "Allow-RDP-Inbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "*"
    },
    {
      name                       = "Allow-Web-Inbound"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    }
  ]

  storage_accounts = [
    {
      name                      = "stsharedavdprofiles"
      account_kind              = "StorageV2"
      account_tier              = "Standard"
      replication_type          = "ZRS"
      enable_https_traffic_only = true
      allow_blob_public_access  = false
      is_hns_enabled            = false
      blob_services = {
        delete_retention_days = 7
      }
    }
  ]

  file_shares = [
    {
      name                 = "profiles"
      storage_account_name = "stsharedavdprofiles"
      quota_gib            = 100
      access_tier          = "Hot"
    }
  ]

  # ---------------------------------------------------------------------------
  # Per-customer Premium FileStorage accounts for FSLogix profile containers
  # ---------------------------------------------------------------------------
  # Each customer gets a dedicated Premium FileStorage account with a "profiles"
  # file share (minimum 100 GiB). This ensures complete data isolation.
  # Account names must be globally unique, 3-24 lowercase alphanumeric characters.
  customer_names = ["contoso", "fabrikam"]

  fslogix_customer_storage_accounts = [
    for name in local.customer_names : {
      name                      = "stfslogix${name}"
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

  fslogix_customer_file_shares = [
    for name in local.customer_names : {
      name                 = "profiles"
      storage_account_name = "stfslogix${name}"
      quota_gib            = 100
      access_tier          = "Premium"
    }
  ]

  # ---------------------------------------------------------------------------
  # Shared App Attach Premium FileStorage account
  # ---------------------------------------------------------------------------
  # One central FileStorage Premium account in the shared spoke for MSIX/App Attach
  # packages, shared across all customers on the shared host pool.
  appattach_storage_account = {
    name                      = "stsharedappattach"
    account_kind              = "FileStorage"
    account_tier              = "Premium"
    replication_type          = "ZRS"
    enable_https_traffic_only = true
    allow_blob_public_access  = false
    min_tls_version           = "TLS1_2"
    is_hns_enabled            = false
    blob_services             = null
  }

  appattach_file_share = {
    name                 = "appattach"
    storage_account_name = "stsharedappattach"
    quota_gib            = 256
    access_tier          = "Premium"
  }

  # Combined Premium storage accounts (per-customer FSLogix + App Attach)
  premium_storage_accounts = concat(
    local.fslogix_customer_storage_accounts,
    [local.appattach_storage_account]
  )

  premium_file_shares = concat(
    local.fslogix_customer_file_shares,
    [local.appattach_file_share]
  )

  # Private endpoint configuration — one PE per Premium storage account, placed
  # in snet-shared-storage and registered in the hub Private DNS Zone.
  # The private_dns_zone_id is supplied at apply time from the hub-and-spoke state.
  # Set it via a terraform.tfvars / variable if you have the hub deployed; leave
  # null to skip DNS group creation until the hub layer is deployed first.
  premium_storage_private_endpoints = [
    for sa in local.premium_storage_accounts : {
      name                 = sa.name
      storage_account_name = sa.name
      subnet_id            = module.networking.subnet_ids["snet-shared-storage"]
      private_dns_zone_id  = var.private_dns_zone_file_id
    }
  ]

  # RBAC: Storage File Data SMB Share Contributor for each customer's principal
  # Assign to the AADDS computer account group / Entra group per customer.
  # principal_ids are provided via var.customer_principal_ids (map of customer → object_id).
  fslogix_rbac_assignments = [
    for name in local.customer_names : {
      name                 = "rbac-fslogix-${name}"
      principal_id         = lookup(var.customer_principal_ids, name, "00000000-0000-0000-0000-000000000000")
      role_definition_name = "Storage File Data SMB Share Contributor"
      storage_account_name = "stfslogix${name}"
    }
  ]

  log_analytics_config = {
    name           = "law-avd-shared"
    sku            = "PerGB2018"
    retention_days = 30
    daily_quota_gb = -1
  }

  action_groups = [
    {
      name       = "ag-avd-alerts"
      short_name = "AVD"
      enabled    = true
      email_receivers = [
        {
          name          = "avd-team"
          email_address = "avd-team@example.com"
        }
      ]
    }
  ]

  session_host_config = [
    {
      vmss_name                   = "vmss-shared-1"
      host_pool_name              = "hp-shared-pool"
      vm_size                     = "Standard_DS2_v2"
      admin_username              = "avdadmin"
      instance_count              = 2
      subnet_id                   = module.networking.subnet_ids["shared-avd"]
      enable_automatic_os_upgrade = true
      zones                       = ["1", "2", "3"]
      tags                        = {}
    }
  ]

  avd_host_pool_resource_ids = [
    for hp in local.host_pool_config : format(
      "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.DesktopVirtualization/hostPools/%s",
      data.azurerm_client_config.current.subscription_id,
      local.resource_group_name,
      hp.name
    )
  ]

  session_host_vmss_resource_ids = [
    for sh in local.session_host_config : format(
      "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Compute/virtualMachineScaleSets/%s",
      data.azurerm_client_config.current.subscription_id,
      local.resource_group_name,
      sh.vmss_name
    )
  ]

  metric_alerts = [
    {
      name        = "alert-avd-session-host-cpu-high"
      description = "Alert when shared AVD session host CPU exceeds 85 percent for 5 minutes"
      severity    = 2
      window_size = "PT5M"
      frequency   = "PT5M"
      scope_ids   = local.session_host_vmss_resource_ids
      criteria = {
        metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
        metric_name      = "Percentage CPU"
        operator         = "GreaterThan"
        threshold        = 85
        aggregation_type = "Average"
      }
      action_group_names = ["ag-avd-alerts"]
    },
    {
      name        = "alert-avd-session-host-memory-low"
      description = "Alert when shared AVD session host available memory drops below 512 MB for 5 minutes"
      severity    = 2
      window_size = "PT5M"
      frequency   = "PT5M"
      scope_ids   = local.session_host_vmss_resource_ids
      criteria = {
        metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
        metric_name      = "Available Memory Bytes"
        operator         = "LessThan"
        threshold        = 536870912
        aggregation_type = "Average"
      }
      action_group_names = ["ag-avd-alerts"]
    },
    {
      name        = "alert-avd-host-pool-connection-failures"
      alert_kind  = "log"
      description = "Alert when shared AVD host pools report user connection failures"
      severity    = 2
      window_size = "PT5M"
      frequency   = "PT5M"
      scope_ids   = local.avd_host_pool_resource_ids
      criteria = {
        query              = <<-KQL
          WVDErrors
          | where ServiceError == false
          | where ActivityType == "Connection"
          | where _ResourceId has "/providers/Microsoft.DesktopVirtualization/hostPools/"
          | project TimeGenerated, _ResourceId, CorrelationId, UserName
        KQL
        resource_id_column = "_ResourceId"
        operator           = "GreaterThan"
        threshold          = 0
        aggregation_type   = "Count"
      }
      action_group_names = ["ag-avd-alerts"]
    }
  ]

  # US-004: Shared host pool is RemoteApp-only (RailApplications) — no Published Desktop.
  # Customers access only the LoB RemoteApp application, not arbitrary desktop sessions.
  host_pool_config = [{
    name                             = "hp-shared-pool"
    friendly_name                    = "Shared AVD Pool"
    description                      = "Shared hosting pool for LoB RemoteApp delivery"
    type                             = "Pooled"
    load_balancer_type               = "BreadthFirst"
    max_session_limit                = 20
    personal_desktop_assignment_type = ""
    preferred_app_group_type         = "RailApplications"
  }]

  workspace_config = [{
    name        = "ws-shared-workspace"
    description = "Shared workspace for AVD"
  }]

  # US-004: RemoteApp application group — no Desktop group created for the shared pool.
  # Per-customer Entra groups are assigned the "Desktop Virtualization User" role on
  # this application group via role assignments in customer.tf.
  application_group_config = [{
    name           = "ag-shared-lob-remoteapp"
    host_pool_name = "hp-shared-pool"
    workspace_name = "ws-shared-workspace"
    type           = "RemoteApp"
    description    = "RemoteApp application group for shared LoB delivery"
  }]

  # US-004: LoB RemoteApp application published inside the RemoteApp application group.
  # Path, command-line arguments, and friendly name are configurable via this local
  # (override via var.lob_application_config at the caller level if needed).
  lob_application_config = {
    application_group_name = "ag-shared-lob-remoteapp"
    name                   = "lob-app"
    friendly_name          = "LoB Application"
    description            = "Corporate line-of-business application delivered via RemoteApp"
    path                   = var.lob_app_path
    command_line_arguments = var.lob_app_command_line_arguments
    command_line_setting   = "Allow"
    show_in_portal         = true
    icon_path              = ""
    icon_index             = 0
  }

  # US-004: Scaling plan — Weekdays: ramp up 07:00, peak 09:00-18:00, ramp down 18:00, off-peak 20:00
  scaling_plan_config = {
    name          = "sp-shared-pool"
    friendly_name = "Shared Pool Business Hours Scaling"
    description   = "Auto-scaling plan for shared AVD pool - business hours (7 AM - 8 PM)"
    time_zone     = "Eastern Standard Time"
    schedules = [
      {
        name                                 = "Weekdays"
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "07:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        ramp_up_minimum_hosts_percent        = 50
        ramp_up_capacity_threshold_percent   = 20
        peak_start_time                      = "09:00"
        peak_load_balancing_algorithm        = "BreadthFirst"
        ramp_down_start_time                 = "18:00"
        ramp_down_load_balancing_algorithm   = "DepthFirst"
        ramp_down_minimum_hosts_percent      = 50
        ramp_down_force_logoff_users         = false
        ramp_down_wait_time_minutes          = 30
        ramp_down_notification_message       = "Your session will be logged off in 30 minutes. Please save your work."
        ramp_down_capacity_threshold_percent = 20
        ramp_down_stop_hosts_when            = "ZeroSessions"
        off_peak_start_time                  = "20:00"
        off_peak_load_balancing_algorithm    = "DepthFirst"
      }
    ]
    host_pools = [
      {
        hostpool_name        = "hp-shared-pool"
        scaling_plan_enabled = true
      }
    ]
  }

  # AADDS Configuration
  aadds_config = {
    domain_name           = "avdshared.local"
    sku                   = "Standard"
    filtered_sync_enabled = false
    ntlm_v1_enabled       = false
    tls_1_2_enabled       = true
    hybrid_sync_enabled   = false
    enable_secure_ldap    = true
  }

  # AADDS replica set configuration (placed in shared-app subnet for management connectivity)
  aadds_replica_set_config = {
    subnet_id = module.networking.subnet_ids["shared-app"]
  }

  # FSLogix Profile Container Configuration
  fslogix_config = {
    storage_account_configs = [
      {
        name              = "stsharedfslogix"
        account_kind      = "FileStorage"
        account_tier      = "Premium"
        replication_type  = "ZRS"
        access_tier       = "Premium"
        enable_https_only = true
        min_tls_version   = "TLS1_2"
        allow_blob_access = false
      }
    ]
    profile_share_configs = [
      {
        name                 = "profiles"
        storage_account_name = "stsharedfslogix"
        quota_gib            = 500
        access_tier          = "Premium"
      }
    ]
    office_container_enabled = true
    office_share_configs = [
      {
        name                 = "office-containers"
        storage_account_name = "stsharedfslogix"
        quota_gib            = 200
        access_tier          = "Premium"
      }
    ]
    enable_private_endpoints     = true
    enable_premium_storage       = true
    enable_geo_redundant         = false
    profile_container_vcpu_quota = 4
    profile_container_max_users  = 20
  }

  # FSLogix rule sets for profile redirection
  fslogix_rule_sets = [
    {
      name        = "shared-desktop-rules"
      description = "FSLogix rules for shared AVD desktop environment"
      rules = [
        {
          include_path = "%username%"
          exclude_path = "AppData\\Local\\Temp;AppData\\Local\\CrashDumps"
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
        }
      ]
    }
  ]

  # Image Builder Configuration for Windows 11 Multisession Golden Image
  image_builder_config = {
    resource_group_name    = "rg-avd-image-builder"
    environment            = "shared"
    create_shared_gallery  = true
    create_staging_storage = true
    replication_regions    = ["eastus", "westeurope"]
    image_publisher        = "MicrosoftWindowsDesktop"
    image_offer            = "windows-11"
    image_sku              = "win11-23h2-avd"
  }
}
