# modules/aadds/outputs.tf — Outputs from the AADDS module.

output "aadds_id" {
  description = "The ID of the Azure AD Domain Services instance"
  value       = azurerm_active_directory_domain_service.this.id
}

output "aadds_name" {
  description = "The name of the Azure AD Domain Services instance"
  value       = azurerm_active_directory_domain_service.this.name
}

output "domain_name" {
  description = "The domain name for the AADDS managed domain"
  value       = azurerm_active_directory_domain_service.this.domain_name
}

output "domain_controller_ips" {
  description = "The IP addresses of the domain controllers"
  value       = azurerm_active_directory_domain_service.this.initial_replica_set[0].domain_controller_ip_addresses
  sensitive   = false
}

output "external_access_ip" {
  description = "The external access IP address for the domain service"
  value       = azurerm_active_directory_domain_service.this.initial_replica_set[0].external_access_ip_address
}

output "deployment_id" {
  description = "The unique deployment ID for the AADDS instance"
  value       = azurerm_active_directory_domain_service.this.deployment_id
}

output "resource_id" {
  description = "The Azure resource ID for the AADDS instance"
  value       = azurerm_active_directory_domain_service.this.resource_id
}

output "service_status" {
  description = "The current service status of the AADDS domain"
  value       = azurerm_active_directory_domain_service.this.initial_replica_set[0].service_status
}

output "sku" {
  description = "The SKU tier of the AADDS instance"
  value       = azurerm_active_directory_domain_service.this.sku
}

output "filtered_sync_enabled" {
  description = "Whether filtered sync is enabled for AADDS"
  value       = azurerm_active_directory_domain_service.this.filtered_sync_enabled
}

output "fslogix_configuration" {
  description = "FSLogix configuration including rule sets and profile container settings"
  value = {
    profile_container_enabled = var.fslogix_config.profile_container_enabled
    office_container_enabled  = var.fslogix_config.office_container_enabled
    profile_share_path        = var.fslogix_config.profile_share_path
    rule_sets                 = local.merged_rule_sets
  }
  sensitive = false
}

output "gpo_configuration" {
  description = "Group Policy Object configurations tracked for AADDS (applied via PowerShell/GPMC)"
  value = {
    for gpo_name, gpo_resource in null_resource.gpo_config :
    gpo_name => {
      name        = gpo_resource.triggers["name"]
      description = gpo_resource.triggers["description"]
    }
  }
}

output "hybrid_sync_enabled" {
  description = "Whether hybrid identity synchronization is enabled"
  value       = var.hybrid_sync_enabled
}

output "on_premises_domain" {
  description = "The on-premises domain that is trusted by AADDS (if hybrid sync enabled)"
  value       = var.on_premises_sync_config.on_prem_domain
  sensitive   = false
}

output "trust_relationship_id" {
  description = "The ID of the trust relationship with on-premises domain (if configured)"
  value       = try(azurerm_active_directory_domain_service_trust.this[0].id, null)
}

output "resource_group_name" {
  description = "The name of the resource group containing AADDS"
  value       = var.resource_group_name
}

output "location" {
  description = "The Azure location of the AADDS instance"
  value       = var.location
}

# Summary output for integration with other modules
output "aadds_integration_config" {
  description = "Configuration summary for integrating AADDS with AVD and other services"
  value = {
    aadds_id              = azurerm_active_directory_domain_service.this.id
    domain_name           = azurerm_active_directory_domain_service.this.domain_name
    domain_controller_ips = azurerm_active_directory_domain_service.this.initial_replica_set[0].domain_controller_ip_addresses
    sku                   = azurerm_active_directory_domain_service.this.sku
    hybrid_sync_enabled   = var.hybrid_sync_enabled
    fslogix_enabled       = var.fslogix_config.profile_container_enabled
    fslogix_share_path    = var.fslogix_config.profile_share_path
  }
}
