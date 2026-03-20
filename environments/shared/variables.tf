# environments/shared/variables.tf — Input variables for the shared AVD environment.

variable "private_dns_zone_file_id" {
  description = <<-EOT
Optional resource ID of the hub Private DNS Zone for privatelink.file.core.windows.net.
When provided, private endpoints created by this environment will register A-records in
the hub DNS zone automatically via a private_dns_zone_group block.

Obtain this value from the networking/hub-and-spoke layer:
  tofu -chdir=networking/hub-and-spoke output private_dns_zone_ids

Leave null (default) when the hub networking layer has not yet been deployed or when
you are running tofu validate / tofu plan without a live backend.
  EOT
  type        = string
  default     = null
}

variable "customer_principal_ids" {
  description = <<-EOT
Map of customer name → Entra Object ID of the group or computer account that should
receive the "Storage File Data SMB Share Contributor" role on that customer's FSLogix
storage account.

Example:
  customer_principal_ids = {
    contoso  = "aaaaaaaa-0000-0000-0000-000000000001"
    fabrikam = "bbbbbbbb-0000-0000-0000-000000000002"
  }

Defaults to an empty map — when a customer entry is missing, the placeholder GUID
"00000000-0000-0000-0000-000000000000" is used, which is safe for validate/plan but
will fail at apply time until real object IDs are supplied.
  EOT
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# US-004: LoB RemoteApp application variables
# ---------------------------------------------------------------------------

variable "lob_app_path" {
  description = <<-EOT
Full path to the LoB application executable on the session hosts.
Example: "C:\\Program Files\\MyApp\\myapp.exe"
  EOT
  type        = string
  default     = "C:\\Windows\\system32\\notepad.exe"
}

variable "lob_app_command_line_arguments" {
  description = <<-EOT
Optional command-line arguments to pass to the LoB application when launched.
Example: "--mode=avd --customer=contoso"
  EOT
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# US-004: Per-customer Entra group object IDs for AVD RemoteApp access
# ---------------------------------------------------------------------------

variable "customer_avd_group_ids" {
  description = <<-EOT
Map of customer name → Entra Object ID of the Entra group that should receive
the "Desktop Virtualization User" role on the shared RemoteApp application group.

Example:
  customer_avd_group_ids = {
    contoso  = "aaaaaaaa-0000-0000-0000-000000000001"
    fabrikam = "bbbbbbbb-0000-0000-0000-000000000002"
  }

Defaults to an empty map — when a customer entry is missing, the placeholder GUID
is used, which is safe for validate/plan but will fail at apply time.
  EOT
  type        = map(string)
  default     = {}
}
