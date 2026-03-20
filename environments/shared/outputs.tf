# environments/shared/outputs.tf — Outputs from the shared AVD environment.

output "resource_group_name" {
  description = "Name of the shared resource group"
  value       = local.resource_group_name
}

output "location" {
  description = "Azure region"
  value       = local.location
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.networking.vnet_name
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = module.networking.subnet_ids
}

output "storage_account_names" {
  description = "Names of the storage accounts"
  value       = module.storage.storage_account_names
}

output "file_share_urls" {
  description = "URLs of the file shares"
  value       = module.storage.file_share_urls
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = module.monitoring.log_analytics_workspace_name
}

output "host_pool_id" {
  description = "ID of the AVD host pool"
  value       = try(module.avd.host_pool_ids["hp-shared-pool"], null)
}

output "host_pool_fqdn" {
  description = "FQDN of the AVD host pool"
  value       = try(module.avd.host_pool_fqdns["hp-shared-pool"], null)
}

output "workspace_url" {
  description = "URL of the AVD workspace"
  value       = try(module.avd.workspace_urls["ws-shared-workspace"], null)
}

output "scaling_plan_id" {
  description = "ID of the AVD scaling plan"
  value       = module.avd.scaling_plan_id
}

# AADDS Outputs
output "aadds_id" {
  description = "ID of the Azure AD Domain Services instance"
  value       = module.aadds.aadds_id
}

output "aadds_domain_name" {
  description = "Domain name of the AADDS instance"
  value       = module.aadds.domain_name
}

output "aadds_domain_controller_ips" {
  description = "IP addresses of the AADDS domain controllers"
  value       = module.aadds.domain_controller_ips
}

output "aadds_integration_config" {
  description = "AADDS integration configuration for AVD and FSLogix"
  value       = module.aadds.aadds_integration_config
}

# FSLogix Outputs (existing fslogix module)
output "fslogix_storage_account_ids" {
  description = "IDs of the FSLogix storage accounts"
  value       = module.fslogix.storage_account_ids
}

output "fslogix_profile_share_endpoints" {
  description = "Endpoints of the FSLogix profile container file shares"
  value       = module.fslogix.profile_container_endpoints
}

output "fslogix_office_share_endpoints" {
  description = "Endpoints of the FSLogix Office container file shares"
  value       = module.fslogix.office_container_endpoints
}

output "fslogix_mount_paths" {
  description = "Mount paths for FSLogix profile and Office containers"
  value       = module.fslogix.fslogix_mount_paths
}

output "fslogix_rule_sets" {
  description = "FSLogix rule sets for profile redirection"
  value       = module.fslogix.rule_sets_configuration
}

output "fslogix_integration_config" {
  description = "Complete FSLogix configuration for integration with AADDS and AVD"
  value       = module.fslogix.fslogix_integration_config
}

# ---------------------------------------------------------------------------
# Per-customer Premium FileStorage + App Attach outputs
# ---------------------------------------------------------------------------
output "premium_storage_account_names" {
  description = "Names of per-customer FSLogix + App Attach Premium storage accounts"
  value       = module.premium_storage.storage_account_names
}

output "premium_storage_file_share_names" {
  description = "Names of per-customer FSLogix profile shares and App Attach share"
  value       = module.premium_storage.file_share_names
}

output "premium_storage_file_share_urls" {
  description = "URLs of per-customer FSLogix profile shares and App Attach share"
  value       = module.premium_storage.file_share_urls
}

output "premium_storage_private_endpoint_ids" {
  description = "IDs of private endpoints for Premium storage accounts"
  value       = module.premium_storage.private_endpoint_ids
}

output "premium_storage_private_endpoint_fqdns" {
  description = "FQDNs of private endpoints for Premium storage accounts (requires hub DNS zone)"
  value       = module.premium_storage.private_endpoint_fqdns
}

# Image Builder Outputs
output "image_builder_resource_group_name" {
  description = "Name of the Image Builder resource group"
  value       = module.image_builder.resource_group_name
}

output "image_builder_resource_group_id" {
  description = "ID of the Image Builder resource group"
  value       = module.image_builder.resource_group_id
}

output "image_builder_template_name" {
  description = "Name of the Image Builder template"
  value       = module.image_builder.image_builder_template_name
}

output "image_builder_template_id" {
  description = "ID of the Image Builder template"
  value       = module.image_builder.image_builder_template_id
}

output "image_builder_managed_identity_id" {
  description = "Resource ID of the Image Builder managed identity"
  value       = module.image_builder.managed_identity_resource_id
}

output "shared_image_gallery_name" {
  description = "Name of the Shared Image Gallery for golden images"
  value       = module.image_builder.shared_image_gallery_name
}

output "shared_image_gallery_id" {
  description = "ID of the Shared Image Gallery for golden images"
  value       = module.image_builder.shared_image_gallery_id
}

output "shared_image_name" {
  description = "Name of the Windows 11 multisession golden image"
  value       = module.image_builder.shared_image_name
}

output "shared_image_id" {
  description = "ID of the Windows 11 multisession golden image"
  value       = module.image_builder.shared_image_id
}

output "staging_storage_account_name" {
  description = "Name of the Image Builder staging storage account"
  value       = module.image_builder.staging_storage_account_name
}

output "staging_storage_endpoint" {
  description = "Blob endpoint of the Image Builder staging storage account"
  value       = module.image_builder.staging_storage_endpoint
}
