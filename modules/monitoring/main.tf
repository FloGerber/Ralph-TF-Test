# modules/monitoring/main.tf — Observability module.
# Provisions: optional Log Analytics Workspace (PerGB2018), action groups with configurable
# email and webhook receivers, and metric alerts with configurable severity, window,
# frequency, and criteria. Diagnostic settings link resource logs/metrics to the workspace.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  metric_alert_rules = {
    for alert in var.metric_alerts : alert.name => alert
    if try(alert.alert_kind, "metric") == "metric"
  }

  log_query_alert_rules = {
    for alert in var.metric_alerts : alert.name => alert
    if try(alert.alert_kind, "metric") == "log"
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_config != null ? 1 : 0

  name                = var.log_analytics_workspace_config.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.log_analytics_workspace_config.sku != null ? var.log_analytics_workspace_config.sku : "PerGB2018"
  retention_in_days   = var.log_analytics_workspace_config.retention_days != null ? var.log_analytics_workspace_config.retention_days : 30

  tags = var.tags
}

resource "azurerm_monitor_action_group" "this" {
  for_each = { for ag in var.action_groups : ag.name => ag }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  short_name          = each.value.short_name
  enabled             = each.value.enabled != null ? each.value.enabled : true

  dynamic "email_receiver" {
    for_each = each.value.email_receivers
    content {
      name          = email_receiver.value.name
      email_address = email_receiver.value.email_address
    }
  }

  dynamic "webhook_receiver" {
    for_each = each.value.webhook_receivers
    content {
      name        = webhook_receiver.value.name
      service_uri = webhook_receiver.value.service_uri
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = local.metric_alert_rules

  name                = each.value.name
  resource_group_name = var.resource_group_name
  description         = each.value.description != null ? each.value.description : ""
  severity            = each.value.severity != null ? each.value.severity : 3
  window_size         = each.value.window_size != null ? each.value.window_size : "PT5M"
  frequency           = each.value.frequency != null ? each.value.frequency : "PT5M"

  enabled = true
  # metric alerts expect resource IDs in `scopes` — default to the resource group's id
  scopes = try(each.value.scope_ids, [data.azurerm_resource_group.this.id])

  criteria {
    metric_namespace = each.value.criteria.metric_namespace != null ? each.value.criteria.metric_namespace : "Microsoft.Compute/virtualMachines"
    metric_name      = each.value.criteria.metric_name
    aggregation      = each.value.criteria.aggregation_type != null ? each.value.criteria.aggregation_type : "Average"
    operator         = each.value.criteria.operator
    threshold        = each.value.criteria.threshold
  }

  dynamic "action" {
    for_each = each.value.action_group_names
    content {
      action_group_id = azurerm_monitor_action_group.this[action.value].id
    }
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  for_each = local.log_query_alert_rules

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  location             = var.location
  description          = each.value.description != null ? each.value.description : ""
  severity             = each.value.severity != null ? each.value.severity : 3
  evaluation_frequency = each.value.frequency != null ? each.value.frequency : "PT5M"
  window_duration      = each.value.window_size != null ? each.value.window_size : "PT5M"
  scopes               = try(each.value.scope_ids, [azurerm_log_analytics_workspace.this[0].id])

  criteria {
    query                   = each.value.criteria.query
    time_aggregation_method = each.value.criteria.aggregation_type != null ? each.value.criteria.aggregation_type : "Count"
    operator                = each.value.criteria.operator
    threshold               = each.value.criteria.threshold
    resource_id_column      = each.value.criteria.resource_id_column != null ? each.value.criteria.resource_id_column : "_ResourceId"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [
      for action_group_name in each.value.action_group_names : azurerm_monitor_action_group.this[action_group_name].id
    ]
  }

  depends_on = [azurerm_log_analytics_workspace.this]
}


// Create diagnostic settings to send resource logs/metrics to the Log Analytics workspace
resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.log_analytics_workspace_config != null ? { for ds in var.diagnostic_settings : ds.name => ds } : {}

  name                       = each.value.name
  target_resource_id         = each.value.target_resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id

  // Per-resource log/metric categories can be added via `diagnostic_settings` entries in the environment.
  // Leaving this resource minimal: workspace link will enable default ingestion for supported resource types.
  // The provider requires at least one of `enabled_log`, `enabled_metric` or `metric` blocks be present
  // in the resource schema even if instances are created conditionally. Provide minimal blocks to
  // satisfy the schema. Specific categories can be added via `diagnostic_settings` entries.
  enabled_metric {
    category = "AllMetrics"
  }

  enabled_log {
    category = "Administrative"
  }

  depends_on = [azurerm_log_analytics_workspace.this]
}

output "environment" {
  description = "Environment label passed to the monitoring module"
  value       = var.environment
}
