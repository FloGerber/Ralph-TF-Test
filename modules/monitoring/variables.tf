# modules/monitoring/variables.tf — Input variables for the monitoring module.

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

variable "log_analytics_workspace_config" {
  description = "Configuration for Log Analytics workspace"
  type = object({
    name           = string
    sku            = optional(string)
    retention_days = optional(number)
    daily_quota_gb = optional(number)
  })
  default = null
}

variable "action_groups" {
  description = "Configuration for action groups"
  type = list(object({
    name       = string
    short_name = string
    enabled    = optional(bool)
    email_receivers = optional(list(object({
      name          = string
      email_address = string
    })), [])
    webhook_receivers = optional(list(object({
      name        = string
      service_uri = string
    })), [])
  }))
  default = []
}

variable "metric_alerts" {
  description = "Configuration for metric alerts"
  type = list(object({
    name        = string
    description = optional(string)
    alert_kind  = optional(string, "metric")
    severity    = optional(number)
    window_size = optional(string)
    frequency   = optional(string)
    scope_ids   = optional(list(string))
    criteria = object({
      metric_name        = optional(string)
      metric_namespace   = optional(string)
      query              = optional(string)
      resource_id_column = optional(string)
      operator           = string
      threshold          = number
      aggregation_type   = optional(string)
    })
    action_group_names = optional(list(string), [])
  }))
  default = []
}

variable "diagnostic_settings" {
  description = "Configuration for diagnostic settings"
  type = list(object({
    name               = string
    target_resource_id = string
  }))
  default = []
}
