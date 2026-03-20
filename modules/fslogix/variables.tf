# modules/fslogix/variables.tf — Input variables for the FSLogix storage module.

variable "location" {
  type = string
}

variable "environment" {
  description = "Environment name (e.g., shared, prod, dev)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group for FSLogix resources"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "storage_account_configs" {
  description = "List of storage accounts for FSLogix profile containers"
  type = list(object({
    name              = string
    account_kind      = optional(string, "StorageV2")
    account_tier      = optional(string, "Premium")
    replication_type  = optional(string, "ZRS")
    access_tier       = optional(string, "Hot")
    enable_https_only = optional(bool, true)
    min_tls_version   = optional(string, "TLS1_2")
    allow_blob_access = optional(bool, false)
  }))
  default = []
}

variable "profile_share_configs" {
  description = "Configuration for profile container file shares"
  type = list(object({
    name                 = string
    storage_account_name = string
    quota_gib            = optional(number, 100)
    access_tier          = optional(string, "Premium")
  }))
  default = []
}

variable "office_container_enabled" {
  description = "Whether to enable Office container for Microsoft 365 app settings"
  type        = bool
  default     = false
}

variable "office_share_configs" {
  description = "Configuration for Office container file shares (when office_container_enabled=true)"
  type = list(object({
    name                 = string
    storage_account_name = string
    quota_gib            = optional(number, 50)
    access_tier          = optional(string, "Premium")
  }))
  default = []
}

variable "rule_sets" {
  description = "FSLogix rule sets defining profile redirect and inclusion/exclusion rules"
  type = list(object({
    name        = string
    description = optional(string, "")
    rules = list(object({
      include_path = string
      exclude_path = optional(string, "")
    }))
  }))
  default = []
}

variable "subnet_id" {
  description = "Subnet ID where FSLogix storage private endpoints will be placed"
  type        = string
  default     = ""
}

variable "enable_private_endpoints" {
  description = "Whether to create private endpoints for storage accounts"
  type        = bool
  default     = true
}

variable "enable_premium_storage" {
  description = "Whether to use Premium storage tier for FSLogix (recommended)"
  type        = bool
  default     = true
}

variable "profile_container_vcpu_quota" {
  description = "Recommended vCPU quota per profile container (used for sizing)"
  type        = number
  default     = 4
}

variable "profile_container_max_users" {
  description = "Maximum concurrent users per profile container"
  type        = number
  default     = 20
}

variable "enable_geo_redundant" {
  description = "Whether to enable geo-redundant storage replication"
  type        = bool
  default     = false
}
