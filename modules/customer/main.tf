# modules/customer/main.tf — Customer onboarding and RBAC module.
# Provisions: per-customer resource groups, admin RBAC role assignments on those resource
# groups, Desktop Virtualization User role assignment on the shared RemoteApp application
# group for the customer's Entra group, and Storage File Data SMB Share Contributor
# assignment on the customer's FSLogix storage account for session host managed identities.

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_resource_group" "customer" {
  for_each = { for c in var.customers : c.name => c }

  name     = "rg-${each.key}"
  location = each.value.location
  tags     = merge(var.tags, each.value.tags)
}

resource "azurerm_role_assignment" "customer_admins" {
  for_each = { for a in var.admin_principals : "${a.customer_name}-${a.principal_id}" => a }

  scope                            = azurerm_resource_group.customer[each.value.customer_name].id
  role_definition_name             = each.value.role_definition_name
  principal_id                     = each.value.principal_id
  skip_service_principal_aad_check = false
}

# ---------------------------------------------------------------------------
# US-010: Per-customer RBAC for multi-tenant isolation
# ---------------------------------------------------------------------------
# Grant the customer's Entra group "Desktop Virtualization User" on the
# RemoteApp application group so that group members can launch published apps.
resource "azurerm_role_assignment" "avd_user" {
  count = var.customer_entra_group_object_id != "" && var.application_group_id != "" ? 1 : 0

  scope                            = var.application_group_id
  role_definition_name             = "Desktop Virtualization User"
  principal_id                     = var.customer_entra_group_object_id
  skip_service_principal_aad_check = false
}

# Grant the customer's Entra group "Storage File Data SMB Share Contributor" on
# the customer-dedicated FSLogix Premium FileStorage account. This is required for
# Kerberos-authenticated SMB access to the FSLogix profile container share.
resource "azurerm_role_assignment" "fslogix_smb" {
  count = var.customer_entra_group_object_id != "" && var.fslogix_storage_account_id != "" ? 1 : 0

  scope                            = var.fslogix_storage_account_id
  role_definition_name             = "Storage File Data SMB Share Contributor"
  principal_id                     = var.customer_entra_group_object_id
  skip_service_principal_aad_check = false
}

output "customer_resource_groups" {
  value = { for name, rg in azurerm_resource_group.customer : name => rg.name }
}
