# modules/dedicated/variables.tf — Input variables for the dedicated AVD composite module.

variable "customer_name" {
  description = "Customer identifier used to derive resource names when a resource_group_name is not provided"
  type        = string
}

variable "user_count" {
  description = "Number of concurrent users for capacity planning (used for auto-scaling configuration)"
  type        = number
  validation {
    condition     = var.user_count > 0
    error_message = "user_count must be greater than 0"
  }
}

variable "avd_image_id" {
  description = "Resource ID of the golden AVD image to use for session hosts"
  type        = string
}

variable "resource_group_name" {
  description = "Optional existing or desired resource group name. If empty a name will be derived from customer_name"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "vnet_config" {
  description = "VNet configuration (address spaces + subnets)"
  type        = any
}

variable "nsg_rules" {
  description = "Network security group rules"
  type        = list(any)
  default     = []
}

variable "storage_account_config" {
  description = "Storage accounts to create. If empty, a Premium FileStorage account will be created for FSLogix"
  type        = list(any)
  default     = []
}

variable "file_shares" {
  description = "File shares to create. If empty, a default profile share will be created for FSLogix"
  type        = list(any)
  default     = []
}

variable "enable_private_endpoints" {
  description = "Whether to create private endpoints for storage accounts"
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_name" {
  description = "Name of the subnet to place private endpoints into (must exist in vnet_config). Defaults to snet-dedicated-storage if present, falls back to dedicated-app."
  type        = string
  default     = "snet-dedicated-storage"
}

variable "private_dns_zone_file_id" {
  description = <<-EOT
Optional resource ID of the hub Private DNS Zone for privatelink.file.core.windows.net.
When provided, private endpoints will register A-records in the hub DNS zone.
  EOT
  type        = string
  default     = null
}

variable "host_pool_config" {
  description = "AVD host pool configuration. If empty, a single Pooled host pool will be created"
  type        = list(any)
  default     = []
}

variable "workspace_config" {
  description = "AVD workspace configuration. If empty, a workspace will be created based on customer_name"
  type        = list(any)
  default     = []
}

variable "application_group_config" {
  description = "AVD application group configuration. If empty, a default app group will be created"
  type        = list(any)
  default     = []
}

variable "session_host_config" {
  description = "Session host scale set configuration for auto-scaling. If empty, will be created with min=1, max=4 based on user_count"
  type        = list(any)
  default     = []
}

variable "hub_vnet_id" {
  description = <<-EOT
Resource ID of the hub VNet to peer with. When provided, VNet peering from the dedicated
spoke to the hub will be created. Leave empty to skip peering.
  EOT
  type        = string
  default     = ""
}

variable "hub_vnet_name" {
  description = <<-EOT
Name of the hub VNet (required for the reverse peering resource).
Must be set when hub_vnet_id is non-empty.
  EOT
  type        = string
  default     = ""
}

variable "aadds_dns_servers" {
  description = <<-EOT
List of AADDS domain controller IP addresses to inject as DNS servers into the
dedicated spoke VNet. These IPs are only known after the AADDS instance is deployed
(second apply pass). Leave empty on first apply.
  EOT
  type        = list(string)
  default     = []
}

variable "hub_firewall_private_ip" {
  description = <<-EOT
Private IP address of the hub Azure Firewall. When provided, a UDR (User Defined Route)
is created routing all spoke traffic (0.0.0.0/0) through the firewall.
  EOT
  type        = string
  default     = ""
}

variable "domain_join_config" {
  description = <<-EOT
Optional AADDS domain join configuration passed through to the AVD session host VMSS.
When provided, each session host VMSS will run a JsonADDomainExtension to join the domain.

Example:
{ domain = "contoso.local", ou_path = "OU=AVD,DC=contoso,DC=local", username = "svc-avd-join@contoso.local", password = "<secret>" }
  EOT
  type = object({
    domain   = string
    ou_path  = optional(string)
    username = string
    password = string
  })
  default   = null
  sensitive = false
}

variable "fslogix_config" {
  description = <<-EOT
Optional FSLogix profile container configuration passed through to the AVD module.
When provided, the FSLogix setup extension is installed on session hosts.

Example:
{ storage_account_name = "stfslogix", file_share_name = "profiles", storage_account_key = "<key>" }
  EOT
  type        = any
  default     = null
}

variable "app_attach_type" {
  description = "App Attach delivery mode forwarded to the AVD module"
  type        = string
  default     = "AppAttach"

  validation {
    condition     = contains(["AppAttach", "MsixAppAttach", "None"], var.app_attach_type)
    error_message = "app_attach_type must be one of: AppAttach, MsixAppAttach, None."
  }
}

variable "app_attach_packages" {
  description = "App Attach packages forwarded to the AVD module"
  type = list(object({
    name = string
    path = string
  }))
  default = []
}

variable "appattach_quota_gib" {
  description = <<-EOT
Quota (GiB) for the optional dedicated App Attach file share on this customer's
storage account. When set to a value greater than 0, a separate "appattach" file
share is added to the customer's FSLogix Premium storage account.
Set to 0 (default) to skip creation of the App Attach share.
  EOT
  type        = number
  default     = 0
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for AVD diagnostic settings"
  type        = string
  default     = ""
}

variable "fslogix_rbac_principal_id" {
  description = <<-EOT
Optional Entra Object ID of the group or computer account that should receive the
"Storage File Data SMB Share Contributor" role on this customer's FSLogix storage
account. Leave empty string to skip the RBAC assignment.
  EOT
  type        = string
  default     = ""
}
