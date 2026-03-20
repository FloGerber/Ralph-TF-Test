# modules/storage/variables.tf — Input variables for the storage module.

variable "location" {
  type = string
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

variable "storage_account_config" {
  description = "Configuration for storage accounts"
  type = list(object({
    name                      = string
    account_kind              = optional(string, "StorageV2")
    account_tier              = optional(string, "Standard")
    replication_type          = optional(string, "ZRS")
    enable_https_traffic_only = optional(bool, true)
    allow_blob_public_access  = optional(bool, false)
    min_tls_version           = optional(string, "TLS1_2")
    is_hns_enabled            = optional(bool, false)
    blob_services = optional(object({
      delete_retention_days = optional(number, 7)
    }), null)
  }))
  default = []
}

variable "file_shares" {
  description = "Configuration for file shares"
  type = list(object({
    name                 = string
    storage_account_name = string
    quota_gib            = optional(number, 100)
    access_tier          = optional(string, "Hot")
  }))
  default = []
}

variable "private_endpoint_config" {
  description = "Configuration for private endpoints"
  type = list(object({
    name                 = string
    storage_account_name = string
    subnet_id            = string
    private_dns_zone_id  = optional(string)
  }))
  default = []
}

variable "rbac_assignments" {
  description = <<-EOT
Optional RBAC assignments to apply to storage accounts or file shares. Each item may
include a `name`, `principal_id`, `role_definition_name` and optional
`storage_account_name` to scope the role to a specific storage account. If
`storage_account_name` is omitted the assignment will be created at the
resource-group level (not recommended for production).
  EOT
  type = list(object({
    name                 = string
    principal_id         = string
    role_definition_name = string
    storage_account_name = optional(string)
  }))
  default = []
}

variable "vnet_ids" {
  description = "List of VNet IDs that should have access to storage"
  type        = list(string)
  default     = []
}

variable "enable_geo_redundant_storage" {
  description = "When true, storage accounts default to geo-redundant replication (RA-GRS) unless explicitly overridden per account"
  type        = bool
  default     = false
}
