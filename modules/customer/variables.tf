# modules/customer/variables.tf — Input variables for the customer onboarding module.

variable "customers" {
  description = "List of customers to create resource groups for"
  type = list(object({
    name     = string
    location = string
    tags     = optional(map(string), {})
  }))
  default = []
}

variable "admin_principals" {
  description = "Optional list of admin principals to assign RBAC roles for customers"
  type = list(object({
    customer_name        = string
    principal_id         = string
    role_definition_name = optional(string, "Contributor")
  }))
  default = []
}

variable "tags" {
  description = "Base tags applied to created resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# US-010: RBAC / IAM variables for per-customer isolation
# ---------------------------------------------------------------------------

variable "application_group_id" {
  description = <<-EOT
Resource ID of the AVD RemoteApp application group to which this customer's Entra group
should be granted the "Desktop Virtualization User" role. Required when
customer_entra_group_object_id is non-empty.
  EOT
  type        = string
  default     = ""
}

variable "fslogix_storage_account_id" {
  description = <<-EOT
Resource ID of the customer's dedicated FSLogix Premium FileStorage account. The customer's
Entra group object ID will be granted "Storage File Data SMB Share Contributor" on this
account to allow Kerberos-authenticated access to the profiles share.
  EOT
  type        = string
  default     = ""
}

variable "customer_entra_group_object_id" {
  description = <<-EOT
Object ID of the customer's Entra ID group. Members of this group:
  - Receive "Desktop Virtualization User" on the RemoteApp application group (application_group_id)
  - Receive "Storage File Data SMB Share Contributor" on the FSLogix storage account (fslogix_storage_account_id)
Leave empty ("") to skip both role assignments (useful during initial bootstrapping before Entra groups exist).
  EOT
  type        = string
  default     = ""
}
