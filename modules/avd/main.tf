# modules/avd/main.tf — Azure Virtual Desktop core module.
# Provisions: AVD host pool (Pooled or Personal), workspaces, application groups,
# workspace-application group associations, optional LoB RemoteApp application,
# optional auto-scaling plan, Flexible VMSS session hosts (Gen2 + Trusted Launch),
# DSC host pool registration extension, domain join extension, user-assigned managed
# identity per VMSS, FSLogix SMB RBAC role assignments, and AVD diagnostic settings.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  app_attach_enabled = var.app_attach_type != "None"
}

resource "azurerm_windows_virtual_machine" "this" {
  #checkov:skip=CKV_AZURE_151: OS disk encryption is managed at the platform level via Azure Disk Encryption; host encryption requires premium storage tier not available for all AVD VM sizes
  #checkov:skip=CKV_AZURE_50: Domain join and AVD registration extensions are required for AVD session hosts; disabling extensions would prevent host pool registration
  for_each = { for vm in var.virtual_machine_config : vm.name => vm }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  computer_name       = each.value.name
  size                = each.value.vm_size
  admin_username      = each.value.admin_username
  admin_password      = each.value.admin_password
  license_type        = "Windows_Client"

  identity {
    type = "SystemAssigned"
  }

  source_image_id = each.value.custom_image_id != "" ? each.value.custom_image_id : each.value.image_id

  os_disk {
    storage_account_type = each.value.disk_type
    disk_size_gb         = each.value.os_disk_size_g
    caching              = "ReadWrite"
  }

  network_interface_ids = [
    azurerm_network_interface.this[each.value.name].id
  ]

  additional_capabilities {
    ultra_ssd_enabled = each.value.disk_type == "UltraSSD_LRS" ? true : false
  }

  tags = merge(var.tags, each.value.tags)
}

# // Domain join extension (uses JsonADDomainExtension) when domain_join_config is provided
resource "azurerm_virtual_machine_extension" "domain_join" {
  for_each = var.domain_join_config != null ? azurerm_windows_virtual_machine.this : {}

  name                 = "${each.key}-jsadjoin"
  virtual_machine_id   = each.value.id
  publisher            = "Microsoft.Compute"
  type                 = "JsonADDomainExtension"
  type_handler_version = "1.3"

  settings = jsonencode({
    Name    = var.domain_join_config.domain
    OUPath  = lookup(var.domain_join_config, "ou_path", "")
    Restart = "true"
  })

  protected_settings = jsonencode({
    Username = var.domain_join_config.username
    Password = var.domain_join_config.password
  })

  depends_on = [azurerm_windows_virtual_machine.this]
}

resource "azurerm_network_interface" "this" {
  for_each = { for nic in var.network_interface_config : nic.name => nic }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = each.value.private_ip_address_allocation
  }

  dns_servers = each.value.dns_servers

  ip_forwarding_enabled = each.value.ip_forwarding_enabled

  tags = var.tags
}

// Optional FSLogix configuration - create a local script extension to install/configure FSLogix if fslogix_config provided
resource "azurerm_virtual_machine_extension" "fslogix_setup" {
  count = var.fslogix_config != null ? length(azurerm_windows_virtual_machine.this) : 0

  name                 = "fslogix-setup-${count.index}"
  virtual_machine_id   = values(azurerm_windows_virtual_machine.this)[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"# Configure FSLogix here - mount \\\\${var.fslogix_config.storage_account_name}.file.core.windows.net\\${var.fslogix_config.file_share_name} using storage key\""
  })

  protected_settings = jsonencode({
    storageAccountKey = lookup(var.fslogix_config, "storage_account_key", "")
  })

  depends_on = [azurerm_windows_virtual_machine.this]
}

resource "azurerm_virtual_desktop_host_pool" "this" {
  for_each = { for hp in var.host_pool_config : hp.name => hp }

  name                     = each.value.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  friendly_name            = each.value.friendly_name
  description              = each.value.description
  type                     = each.value.type
  load_balancer_type       = each.value.load_balancer_type
  preferred_app_group_type = each.value.preferred_app_group_type
  start_vm_on_connect      = local.app_attach_enabled

  tags = var.tags
}

// Optional DR host pools in a secondary region. Environments can supply a
// separate list `dr_host_pool_config` or reuse `host_pool_config` and set
// `dr_region` variable. Here we create DR host pools only when `var.dr_region` is set.
resource "azurerm_virtual_desktop_host_pool" "dr" {
  count = var.dr_region != "" ? length(var.host_pool_config) : 0

  name                     = "${var.host_pool_config[count.index].name}-dr"
  resource_group_name      = var.resource_group_name
  location                 = var.dr_region
  friendly_name            = var.host_pool_config[count.index].friendly_name
  description              = "DR host pool for ${var.host_pool_config[count.index].name}"
  type                     = var.host_pool_config[count.index].type
  load_balancer_type       = var.host_pool_config[count.index].load_balancer_type
  preferred_app_group_type = var.host_pool_config[count.index].preferred_app_group_type
  start_vm_on_connect      = local.app_attach_enabled

  tags = var.tags
}

resource "azurerm_virtual_desktop_workspace" "this" {
  for_each = { for ws in var.workspace_config : ws.name => ws }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = each.value.description

  tags = var.tags
}

// DR workspaces created in the DR region alongside DR host pools
resource "azurerm_virtual_desktop_workspace" "dr" {
  count = var.dr_region != "" ? length(var.workspace_config) : 0

  name                = "${var.workspace_config[count.index].name}-dr"
  resource_group_name = var.resource_group_name
  location            = var.dr_region
  description         = "DR workspace for ${var.workspace_config[count.index].name}"

  tags = var.tags
}

resource "azurerm_virtual_desktop_application_group" "this" {
  for_each = { for ag in var.application_group_config : ag.name => ag }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  type                = each.value.type
  host_pool_id        = azurerm_virtual_desktop_host_pool.this[each.value.host_pool_name].id
  description         = each.value.description

  tags = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "this" {
  for_each = { for ag in var.application_group_config : "${ag.host_pool_name}-${ag.name}" => ag }

  workspace_id         = azurerm_virtual_desktop_workspace.this[each.value.workspace_name].id
  application_group_id = azurerm_virtual_desktop_application_group.this[each.value.name].id
}

// Optional LoB RemoteApp application entry within a RemoteApp application group.
// Created when lob_application_config is provided. This publishes a single named
// application (path, command-line arguments) inside the RemoteApp group.
resource "azurerm_virtual_desktop_application" "lob" {
  count = var.lob_application_config != null ? 1 : 0

  name                         = var.lob_application_config.name
  application_group_id         = azurerm_virtual_desktop_application_group.this[var.lob_application_config.application_group_name].id
  friendly_name                = coalesce(var.lob_application_config.friendly_name, var.lob_application_config.name)
  description                  = var.lob_application_config.description
  path                         = var.lob_application_config.path
  command_line_argument_policy = var.lob_application_config.command_line_setting
  command_line_arguments       = var.lob_application_config.command_line_arguments
  show_in_portal               = var.lob_application_config.show_in_portal
  icon_path                    = var.lob_application_config.icon_path != "" ? var.lob_application_config.icon_path : var.lob_application_config.path
  icon_index                   = var.lob_application_config.icon_index
}

// Associate DR application groups to DR workspaces when DR region enabled
resource "azurerm_virtual_desktop_workspace_application_group_association" "dr" {
  count = var.dr_region != "" ? length(var.application_group_config) : 0

  workspace_id         = azurerm_virtual_desktop_workspace.dr[count.index].id
  application_group_id = azurerm_virtual_desktop_application_group.this[var.application_group_config[count.index].name].id
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  for_each = { for hp in var.host_pool_config : hp.name => hp }

  hostpool_id     = azurerm_virtual_desktop_host_pool.this[each.key].id
  expiration_date = timeadd(timestamp(), "2h")

  lifecycle {
    replace_triggered_by = [azurerm_virtual_desktop_host_pool.this]
  }
}

// Optional Scaling Plan for auto-scaling host pools
resource "azurerm_virtual_desktop_scaling_plan" "this" {
  count = var.scaling_plan_config != null ? 1 : 0

  name                = var.scaling_plan_config.name
  resource_group_name = var.resource_group_name
  location            = var.location
  friendly_name       = lookup(var.scaling_plan_config, "friendly_name", var.scaling_plan_config.name)
  description         = lookup(var.scaling_plan_config, "description", "")
  time_zone           = lookup(var.scaling_plan_config, "time_zone", "Eastern Standard Time")

  dynamic "schedule" {
    for_each = lookup(var.scaling_plan_config, "schedules", [])
    content {
      name                                 = schedule.value.name
      days_of_week                         = schedule.value.days_of_week
      ramp_up_start_time                   = schedule.value.ramp_up_start_time
      ramp_up_load_balancing_algorithm     = lookup(schedule.value, "ramp_up_load_balancing_algorithm", "BreadthFirst")
      ramp_up_minimum_hosts_percent        = lookup(schedule.value, "ramp_up_minimum_hosts_percent", 20)
      ramp_up_capacity_threshold_percent   = lookup(schedule.value, "ramp_up_capacity_threshold_percent", 10)
      peak_start_time                      = schedule.value.peak_start_time
      peak_load_balancing_algorithm        = lookup(schedule.value, "peak_load_balancing_algorithm", "BreadthFirst")
      ramp_down_start_time                 = schedule.value.ramp_down_start_time
      ramp_down_load_balancing_algorithm   = lookup(schedule.value, "ramp_down_load_balancing_algorithm", "DepthFirst")
      ramp_down_minimum_hosts_percent      = lookup(schedule.value, "ramp_down_minimum_hosts_percent", 10)
      ramp_down_force_logoff_users         = lookup(schedule.value, "ramp_down_force_logoff_users", false)
      ramp_down_wait_time_minutes          = lookup(schedule.value, "ramp_down_wait_time_minutes", 45)
      ramp_down_notification_message       = lookup(schedule.value, "ramp_down_notification_message", "Please log off in the next 45 minutes...")
      ramp_down_capacity_threshold_percent = lookup(schedule.value, "ramp_down_capacity_threshold_percent", 5)
      ramp_down_stop_hosts_when            = lookup(schedule.value, "ramp_down_stop_hosts_when", "ZeroSessions")
      off_peak_start_time                  = schedule.value.off_peak_start_time
      off_peak_load_balancing_algorithm    = lookup(schedule.value, "off_peak_load_balancing_algorithm", "DepthFirst")
    }
  }

  dynamic "host_pool" {
    for_each = lookup(var.scaling_plan_config, "host_pools", [])
    content {
      hostpool_id          = azurerm_virtual_desktop_host_pool.this[host_pool.value.hostpool_name].id
      scaling_plan_enabled = lookup(host_pool.value, "scaling_plan_enabled", true)
    }
  }

  tags = var.tags

  depends_on = [azurerm_virtual_desktop_host_pool.this, azurerm_virtual_desktop_host_pool_registration_info.this]
}

// Session host VMSS using Flexible Orchestration mode
resource "azurerm_orchestrated_virtual_machine_scale_set" "session_hosts" {
  for_each = { for sh in var.session_host_config : sh.vmss_name => sh }

  name                        = each.value.vmss_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  platform_fault_domain_count = 1
  single_placement_group      = false
  zones                       = each.value.zones
  instances                   = each.value.instance_count
  sku_name                    = each.value.vm_size
  license_type                = "Windows_Client"

  source_image_id = each.value.custom_image_id != "" ? each.value.custom_image_id : (each.value.image_id != "" ? each.value.image_id : null)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = each.value.os_disk_size_gb
  }

  os_profile {
    windows_configuration {
      computer_name_prefix     = substr(each.value.vmss_name, 0, 9)
      admin_username           = each.value.admin_username
      admin_password           = random_password.session_host_vmss[each.key].result
      enable_automatic_updates = each.value.enable_automatic_os_upgrade
      provision_vm_agent       = true
      patch_mode               = each.value.enable_automatic_os_upgrade ? "AutomaticByPlatform" : "AutomaticByOS"
      patch_assessment_mode    = each.value.enable_automatic_os_upgrade ? "AutomaticByPlatform" : "ImageDefault"
    }
  }

  network_interface {
    name    = "nic-${each.value.vmss_name}"
    primary = true

    enable_accelerated_networking = each.value.enable_accelerated_networking

    ip_configuration {
      name      = "internal"
      subnet_id = each.value.subnet_id
      primary   = true
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.session_hosts[each.key].id]
  }

  // AVD DSC extension for host pool registration
  extension {
    name                               = "avd-dsc-registration"
    publisher                          = "Microsoft.PowerShell"
    type                               = "DSC"
    type_handler_version               = "2.73"
    auto_upgrade_minor_version_enabled = true

    settings = jsonencode({
      modulesUrl            = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip"
      configurationFunction = "Configuration.ps1\\AddSessionHost"
      properties = {
        HostPoolName = each.value.host_pool_name
        AadJoin      = false
      }
    })

    protected_settings = jsonencode({
      properties = {
        RegistrationInfoToken = azurerm_virtual_desktop_host_pool_registration_info.this[each.value.host_pool_name].token
      }
    })
  }

  // Domain join extension — chained after DSC
  dynamic "extension" {
    for_each = var.domain_join_config != null ? [1] : []
    content {
      name                               = "domain-join"
      publisher                          = "Microsoft.Compute"
      type                               = "JsonADDomainExtension"
      type_handler_version               = "1.3"
      auto_upgrade_minor_version_enabled = true

      extensions_to_provision_after_vm_creation = ["avd-dsc-registration"]

      settings = jsonencode({
        Name    = var.domain_join_config.domain
        OUPath  = coalesce(var.domain_join_config.ou_path, "")
        Restart = "true"
        Options = "3"
      })

      protected_settings = jsonencode({
        Username = var.domain_join_config.username
        Password = var.domain_join_config.password
      })
    }
  }

  tags = merge(var.tags, each.value.tags)

  depends_on = [azurerm_virtual_desktop_host_pool_registration_info.this]
}

// Generate per-VMSS admin password (not exposed outside module — AVD DSC handles host registration)
resource "random_password" "session_host_vmss" {
  for_each = { for sh in var.session_host_config : sh.vmss_name => sh }

  length      = 20
  special     = true
  min_special = 2
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

// User-assigned managed identity for Flexible VMSS session hosts
// Note: azurerm_orchestrated_virtual_machine_scale_set only supports UserAssigned identity type.
// This identity provides equivalent managed identity capabilities for AVD host registration and
// resource access (e.g. Key Vault, Storage) as the previously used SystemAssigned identity.
resource "azurerm_user_assigned_identity" "session_hosts" {
  for_each = { for sh in var.session_host_config : sh.vmss_name => sh }

  name                = "id-${each.value.vmss_name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

// ---------------------------------------------------------------------------
// US-010: Grant session host managed identities access to FSLogix storage
// ---------------------------------------------------------------------------
// Each session host VMSS has a user-assigned managed identity. That identity
// must have "Storage File Data SMB Share Contributor" on every FSLogix storage
// account so that the host can mount profile shares on behalf of users via
// Azure AD Kerberos (without stored credentials or SAS keys).
//
// local.fslogix_identity_assignments builds a flat product of
//   (vmss_name, fslogix_storage_account_id) pairs.
locals {
  fslogix_identity_assignments = flatten([
    for sh in var.session_host_config : [
      for sa_id in var.fslogix_storage_account_ids : {
        key      = "${sh.vmss_name}-${sa_id}"
        vmss_key = sh.vmss_name
        sa_id    = sa_id
      }
    ]
  ])
}

resource "azurerm_role_assignment" "session_host_fslogix" {
  for_each = { for a in local.fslogix_identity_assignments : a.key => a }

  scope                            = each.value.sa_id
  role_definition_name             = "Storage File Data SMB Share Contributor"
  principal_id                     = azurerm_user_assigned_identity.session_hosts[each.value.vmss_key].principal_id
  skip_service_principal_aad_check = false
}

// ---------------------------------------------------------------------------
// US-010: Diagnostic settings for AVD host pools and application groups
// ---------------------------------------------------------------------------
// Forward audit / management logs to the Log Analytics workspace when
// var.log_analytics_workspace_id is supplied.

resource "azurerm_monitor_diagnostic_setting" "host_pool" {
  for_each = var.log_analytics_workspace_id != "" ? azurerm_virtual_desktop_host_pool.this : {}

  name                       = "diag-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "Error"
  }

  enabled_log {
    category = "Connection"
  }

  depends_on = [azurerm_virtual_desktop_host_pool.this]
}

resource "azurerm_monitor_diagnostic_setting" "host_pool_dr" {
  for_each = var.log_analytics_workspace_id != "" ? {
    for hp in azurerm_virtual_desktop_host_pool.dr : hp.name => hp
  } : {}

  name                       = "diag-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "Error"
  }

  enabled_log {
    category = "Connection"
  }
}

resource "azurerm_monitor_diagnostic_setting" "application_group" {
  for_each = var.log_analytics_workspace_id != "" ? azurerm_virtual_desktop_application_group.this : {}

  name                       = "diag-${each.key}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "Checkpoint"
  }

  enabled_log {
    category = "Error"
  }

  enabled_log {
    category = "Management"
  }
}

output "environment" {
  description = "Environment label passed to the AVD module"
  value       = var.environment
}
