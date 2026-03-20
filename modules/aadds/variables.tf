# modules/aadds/variables.tf — Input variables for the AADDS module.

variable "location" {
  type = string
}

variable "environment" {
  description = "Environment name (e.g., shared, prod, dev)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group for AADDS resources"
  type        = string
}

variable "create_resource_group" {
  description = "Whether to create the resource group inside this module. Set to false when the resource group is managed externally (e.g., by the hub-and-spoke networking layer)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "domain_name" {
  description = "AADDS managed domain name (e.g., contoso.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.domain_name))
    error_message = "Domain name must be a valid domain format"
  }
}

variable "aadds_subnet_id" {
  description = "Subnet ID for the AADDS managed domain (snet-aadds, 10.0.5.0/24). Must have NSG allowing TCP 636, TCP/UDP 389, TCP/UDP 88, TCP/UDP 53. When provided, takes precedence over replica_set_config.subnet_id."
  type        = string
  default     = ""
}

variable "replica_set_config" {
  description = "Configuration for AADDS replica set. Use aadds_subnet_id for the primary subnet; this field is kept for backwards compatibility."
  type = object({
    subnet_id = string
    tags      = optional(map(string), {})
  })
  default = {
    subnet_id = ""
  }
}

variable "sku" {
  description = "SKU for AADDS (Standard or Enterprise)"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Enterprise"], var.sku)
    error_message = "SKU must be either Standard or Enterprise"
  }
}

variable "filtered_sync_enabled" {
  description = "Whether filtered sync is enabled for AADDS"
  type        = bool
  default     = false
}

variable "ntlm_v1_enabled" {
  description = "Whether NTLM v1 is enabled (legacy support)"
  type        = bool
  default     = false
}

variable "tls_1_2_enabled" {
  description = "Whether to enforce TLS 1.2 for LDAP connections"
  type        = bool
  default     = true
}

variable "gpo_config" {
  description = "Group Policy Object configuration for security baselines"
  type = list(object({
    name        = string
    description = string
    policies = optional(list(object({
      policy_name = string
      setting     = string
      value       = string
    })), [])
  }))
  default = []
}

variable "fslogix_config" {
  description = "FSLogix configuration for user profiles and containers"
  type = object({
    profile_container_enabled = optional(bool, true)
    office_container_enabled  = optional(bool, false)
    profile_share_path        = optional(string, "")
    rule_sets = optional(list(object({
      name        = string
      description = optional(string, "")
      rules = list(object({
        include_path = string
        exclude_path = optional(string, "")
      }))
    })), [])
  })
  default = {}
}

variable "hybrid_sync_enabled" {
  description = "Whether to enable hybrid identity synchronization from on-premises"
  type        = bool
  default     = false
}

variable "on_premises_sync_config" {
  description = "Configuration for on-premises AD synchronization"
  type = object({
    sync_enabled    = optional(bool, false)
    on_prem_domain  = optional(string, "")
    forest_name     = optional(string, "")
    sync_user_email = optional(string, "")
    sync_password   = optional(string, "")
    sync_url        = optional(string, "")
  })
  default = {}
}
