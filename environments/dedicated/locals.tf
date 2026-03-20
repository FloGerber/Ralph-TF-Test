# environments/dedicated/locals.tf — Local values for the dedicated AVD environment.
# Contains base configuration for the default dedicated environment (networking, storage,
# AVD host pool / workspace / app groups, monitoring). Per-customer dedicated environments
# are defined in customer-example.tf using modules/dedicated.

locals {
  environment         = "dedicated"
  location            = "eastus"
  resource_group_name = "rg-avd-dedicated"

  tags = {
    Environment = "Production"
    Project     = "AVD"
    ManagedBy   = "OpenTofu"
    HostingType = "Dedicated"
  }

  vnet_config = {
    address_spaces = ["10.2.0.0/16"]
    subnets = [
      {
        name              = "dedicated-app"
        address_prefixes  = ["10.2.1.0/24"]
        service_endpoints = ["Microsoft.Storage"]
        delegations       = []
      },
      {
        name              = "dedicated-avd"
        address_prefixes  = ["10.2.2.0/24"]
        service_endpoints = ["Microsoft.Storage"]
        delegations       = ["Microsoft.WindowsVirtualDesktop/hostPools"]
      },
      {
        name              = "AzureBastionSubnet"
        address_prefixes  = ["10.2.3.0/24"]
        service_endpoints = []
        delegations       = []
      },
      {
        # Dedicated subnet for FSLogix + App Attach private endpoints
        name              = "snet-dedicated-storage"
        address_prefixes  = ["10.2.4.0/24"]
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
    },
    {
      name                       = "Allow-App-Inbound"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "8080"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "*"
    }
  ]

  storage_accounts = [
    {
      name                      = "stdedicatedavdprofiles"
      account_kind              = "StorageV2"
      account_tier              = "Standard"
      replication_type          = "ZRS"
      enable_https_traffic_only = true
      allow_blob_public_access  = false
      is_hns_enabled            = false
      blob_services = {
        delete_retention_days = 30
      }
    }
  ]

  file_shares = [
    {
      name                 = "profiles"
      storage_account_name = "stdedicatedavdprofiles"
      quota_gib            = 500
      access_tier          = "Hot"
    },
    {
      name                 = "corporate-data"
      storage_account_name = "stdedicatedavdprofiles"
      quota_gib            = 1000
      access_tier          = "Hot"
    }
  ]

  log_analytics_config = {
    name           = "law-avd-dedicated"
    sku            = "PerGB2018"
    retention_days = 90
    daily_quota_gb = -1
  }

  action_groups = [
    {
      name       = "ag-avd-critical"
      short_name = "AVD-CRIT"
      enabled    = true
      email_receivers = [
        {
          name          = "avd-operations"
          email_address = "avd-operations@example.com"
        }
      ]
      webhook_receivers = [
        {
          name        = "avd-slack"
          service_uri = "https://hooks.slack.com/services/example"
        }
      ]
    }
  ]

  metric_alerts = [
    {
      name        = "alert-cpu-utilization"
      description = "Alert when CPU utilization is high"
      severity    = 2
      window_size = "PT5M"
      frequency   = "PT5M"
      criteria = {
        metric_name      = "Percentage CPU"
        operator         = "GreaterThan"
        threshold        = 80
        aggregation_type = "Average"
      }
      action_group_names = ["ag-avd-critical"]
    },
    {
      name        = "alert-memory-utilization"
      description = "Alert when memory utilization is high"
      severity    = 2
      window_size = "PT5M"
      frequency   = "PT5M"
      criteria = {
        metric_name      = "Available Memory Bytes"
        operator         = "LessThan"
        threshold        = 2147483648
        aggregation_type = "Average"
      }
      action_group_names = ["ag-avd-critical"]
    }
  ]

  host_pool_config = [{
    name                             = "hp-dedicated-pool"
    friendly_name                    = "Dedicated AVD Pool"
    description                      = "Dedicated hosting pool for AVD"
    type                             = "Personal"
    load_balancer_type               = "DepthFirst"
    max_session_limit                = 1
    personal_desktop_assignment_type = "Automatic"
    preferred_app_group_type         = "Desktop"
  }]

  workspace_config = [{
    name        = "ws-dedicated-workspace"
    description = "Dedicated workspace for AVD"
  }]

  application_group_config = [
    {
      name           = "ag-dedicated-desktop"
      host_pool_name = "hp-dedicated-pool"
      workspace_name = "ws-dedicated-workspace"
      type           = "Desktop"
      description    = "Desktop application group for dedicated hosting"
    },
    {
      name           = "ag-dedicated-apps"
      host_pool_name = "hp-dedicated-pool"
      workspace_name = "ws-dedicated-workspace"
      type           = "RemoteApp"
      description    = "RemoteApp application group for dedicated hosting"
    }
  ]
}
