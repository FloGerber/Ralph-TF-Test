# modules/avd/outputs.tf — Outputs from the AVD core module.

output "host_pool_ids" {
  description = "IDs of the AVD host pools"
  value       = { for name, hp in azurerm_virtual_desktop_host_pool.this : name => hp.id }
}

output "host_pool_names" {
  description = "Names of the AVD host pools"
  value       = { for name, hp in azurerm_virtual_desktop_host_pool.this : name => hp.name }
}

output "host_pool_fqdns" {
  description = "FQDNs of the AVD host pools"
  value       = { for name, hp in azurerm_virtual_desktop_host_pool.this : name => try(hp.fqdn, null) }
}

output "workspace_ids" {
  description = "IDs of the AVD workspaces"
  value       = { for name, ws in azurerm_virtual_desktop_workspace.this : name => ws.id }
}

output "workspace_urls" {
  description = "URLs of the AVD workspaces"
  value       = { for name, ws in azurerm_virtual_desktop_workspace.this : name => try(ws.workspace_url, null) }
}

output "application_group_ids" {
  description = "IDs of the AVD application groups"
  value       = { for name, ag in azurerm_virtual_desktop_application_group.this : name => ag.id }
}

output "virtual_machine_ids" {
  description = "IDs of the virtual machines"
  value       = { for name, vm in azurerm_windows_virtual_machine.this : name => vm.id }
}

output "session_host_vmss_ids" {
  description = "IDs of the Flexible Orchestration VMSS session hosts"
  value       = { for name, vmss in azurerm_orchestrated_virtual_machine_scale_set.session_hosts : name => vmss.id }
}

output "session_host_identity_ids" {
  description = "IDs of the user-assigned managed identities for session host VMSSes"
  value       = { for name, id in azurerm_user_assigned_identity.session_hosts : name => id.id }
}

output "session_host_identity_principal_ids" {
  description = "Principal IDs of the user-assigned managed identities for session host VMSSes"
  value       = { for name, id in azurerm_user_assigned_identity.session_hosts : name => id.principal_id }
}

output "app_attach_packages" {
  description = "App Attach package metadata passed to the module"
  value       = var.app_attach_packages
}

output "registration_token" {
  description = "Registration token for the host pool"
  value       = try(azurerm_virtual_desktop_host_pool_registration_info.this[keys(azurerm_virtual_desktop_host_pool_registration_info.this)[0]].token, null)
  sensitive   = true
}

output "scaling_plan_id" {
  description = "ID of the Virtual Desktop Scaling Plan"
  value       = try(azurerm_virtual_desktop_scaling_plan.this[0].id, null)
}
