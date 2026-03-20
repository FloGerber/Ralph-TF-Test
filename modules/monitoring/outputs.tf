# modules/monitoring/outputs.tf — Outputs from the monitoring module.

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.this[0].id, null)
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.this[0].name, null)
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = try(azurerm_log_analytics_workspace.this[0].primary_shared_key, null)
  sensitive   = true
}

output "action_group_ids" {
  description = "IDs of the action groups"
  value       = { for name, ag in azurerm_monitor_action_group.this : name => ag.id }
}

output "metric_alert_ids" {
  description = "IDs of the metric alerts"
  value       = { for name, alert in azurerm_monitor_metric_alert.this : name => alert.id }
}
