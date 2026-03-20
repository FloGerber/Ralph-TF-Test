# modules/avd/variables.tf — Input variables for the AVD core module.

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "host_pool_config" {
  description = "Configuration for AVD host pools"
  type = list(object({
    name                             = string
    friendly_name                    = optional(string, "")
    description                      = optional(string, "")
    type                             = string
    load_balancer_type               = string
    max_session_limit                = optional(number, 99999)
    personal_desktop_assignment_type = optional(string, "")
    preferred_app_group_type         = optional(string, "Desktop")
    scheduling_mechanism             = optional(string, "DepthFirst")
    vm_template = optional(object({
      name                  = string
      custom_script_uri     = optional(string, "")
      custom_script_command = optional(string, "")
    }), null)
  }))
  default = []
}

variable "workspace_config" {
  description = "Configuration for AVD workspaces"
  type = list(object({
    name        = string
    description = optional(string, "")
  }))
  default = []
}

variable "application_group_config" {
  description = "Configuration for AVD application groups"
  type = list(object({
    name           = string
    host_pool_name = string
    # workspace_name: name of the workspace this application group is associated with.
    # Must match an entry in workspace_config.
    workspace_name = string
    type           = string
    description    = optional(string, "")
  }))
  default = []
}

variable "lob_application_config" {
  description = <<-EOT
Optional configuration for a Line-of-Business (LoB) RemoteApp application to publish
inside a RemoteApp application group. When provided, an azurerm_virtual_desktop_application
resource is created.

Example:
  lob_application_config = {
    application_group_name = "ag-shared-lob-remoteapp"
    name                   = "lob-app"
    friendly_name          = "My LoB Application"
    description            = "Corporate line-of-business application"
    path                   = "C:\\Program Files\\LOBApp\\app.exe"
    command_line_arguments = "--mode=avd"
    command_line_setting   = "Allow"
    show_in_portal         = true
    icon_path              = "C:\\Program Files\\LOBApp\\app.exe"
    icon_index             = 0
  }
  EOT
  type = object({
    application_group_name = string
    name                   = string
    friendly_name          = optional(string, "")
    description            = optional(string, "")
    path                   = string
    command_line_arguments = optional(string, "")
    command_line_setting   = optional(string, "DoNotAllow")
    show_in_portal         = optional(bool, true)
    icon_path              = optional(string, "")
    icon_index             = optional(number, 0)
  })
  default = null
}

variable "app_attach_type" {
  description = "App Attach delivery mode for the host pool"
  type        = string
  default     = "AppAttach"

  validation {
    condition     = contains(["AppAttach", "MsixAppAttach", "None"], var.app_attach_type)
    error_message = "app_attach_type must be one of: AppAttach, MsixAppAttach, None."
  }
}

variable "app_attach_packages" {
  description = "App Attach packages published to the AVD environment"
  type = list(object({
    name = string
    path = string
  }))
  default = []
}

variable "virtual_machine_config" {
  description = "Configuration for AVD virtual machines"
  type = list(object({
    name                          = string
    host_pool_name                = string
    vm_size                       = string
    admin_username                = string
    admin_password                = string
    image_id                      = optional(string, "")
    custom_image_id               = optional(string, "")
    subnet_id                     = string
    availability_set_id           = optional(string, "")
    disk_type                     = optional(string, "StandardSSD_LRS")
    disk_size_gb                  = optional(number, 128)
    os_disk_size_gb               = optional(number, 128)
    enable_accelerated_networking = optional(bool, true)
    enable_autoscale              = optional(bool, false)
    min_instances                 = optional(number, 0)
    max_instances                 = optional(number, 3)
    tags                          = optional(map(string), {})
  }))
  default = []
}

variable "network_interface_config" {
  description = "Configuration for network interfaces"
  type = list(object({
    name                          = string
    vm_name                       = string
    subnet_id                     = string
    ip_forwarding_enabled         = optional(bool, false)
    enable_accelerated_networking = optional(bool, true)
    private_ip_address_allocation = optional(string, "Dynamic")
    dns_servers                   = optional(list(string), [])
  }))
  default = []
}

variable "domain_join_config" {
  description = "Configuration for domain joining"
  type = object({
    domain   = string
    ou_path  = optional(string)
    username = string
    password = string
  })
  default = null
}

variable "fslogix_config" {
  description = <<-EOT
Optional FSLogix profile container configuration. Example:
{ storage_account_name = "stdedicatedavdprofiles", file_share_name = "profiles", storage_account_key = "<key>" }
  EOT
  type        = any
  default     = null
}

variable "session_host_config" {
  description = "Configuration for session host scale sets (Flexible Orchestration VMSS)"
  type = list(object({
    vmss_name                     = string
    host_pool_name                = string
    vm_size                       = optional(string, "Standard_D4s_v3")
    admin_username                = string
    instance_count                = optional(number, 2)
    image_id                      = optional(string, "")
    custom_image_id               = optional(string, "")
    subnet_id                     = string
    os_disk_size_gb               = optional(number, 128)
    enable_accelerated_networking = optional(bool, true)
    enable_automatic_os_upgrade   = optional(bool, true)
    zones                         = optional(list(string), ["1", "2", "3"])
    tags                          = optional(map(string), {})
  }))
  default = []
}

variable "scaling_plan_config" {
  description = "Optional configuration for AVD scaling plans for auto-scaling host pools. Example: { name = 'sp-shared', friendly_name = 'Shared Scaling Plan', time_zone = 'Eastern Standard Time', schedules = [...], host_pools = [{hostpool_name = 'hp-shared-pool', scaling_plan_enabled = true}] }"
  type        = any
  default     = null
}

variable "dr_region" {
  description = "Name of the DR/secondary Azure region to deploy AVD control plane and host pools into (optional). If empty, DR resources will not be created. Environments can set this to deploy DR host pools in a secondary region."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# US-010: RBAC for session host managed identities
# ---------------------------------------------------------------------------
variable "fslogix_storage_account_ids" {
  description = <<-EOT
List of FSLogix Premium FileStorage account resource IDs to which the session host
user-assigned managed identities should be granted "Storage File Data SMB Share Contributor".
This allows session hosts to mount FSLogix profile shares using their managed identity
(Kerberos over SMB / Azure AD Kerberos) without requiring stored credentials.

Example:
  fslogix_storage_account_ids = [
    "/subscriptions/.../resourceGroups/.../providers/Microsoft.Storage/storageAccounts/stfslogixcontoso",
    "/subscriptions/.../resourceGroups/.../providers/Microsoft.Storage/storageAccounts/stfslogixfabrikam",
  ]

Leave empty (default) to skip the role assignments.
  EOT
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for AVD diagnostic settings"
  type        = string
  default     = ""
}
