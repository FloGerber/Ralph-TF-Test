# environments/shared/customer.tf — Customer factory and per-customer RBAC for shared AVD.
# Instantiates modules/customer to create per-customer resource groups and RBAC assignments.
# Add new customers to the customer_names list in locals.tf and customer_avd_group_ids variable.

module "customer_factory" {
  source = "../../modules/customer"

  customers = [
    {
      name     = "contoso"
      location = local.location
      tags     = merge(local.tags, { Customer = "contoso" })
    },
    {
      name     = "fabrikam"
      location = local.location
      tags     = merge(local.tags, { Customer = "fabrikam" })
    }
  ]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# US-004: Per-customer "Desktop Virtualization User" role assignments
# ---------------------------------------------------------------------------
# Each customer Entra group gets the Desktop Virtualization User built-in role
# on the shared RemoteApp application group. This allows group members to
# launch the published LoB RemoteApp but does NOT grant desktop session access.
#
# Entra group object IDs are supplied via var.customer_avd_group_ids.
# Missing entries default to the placeholder GUID (safe for plan; will fail apply).
locals {
  customer_names_for_avd = ["contoso", "fabrikam"]
}

resource "azurerm_role_assignment" "customer_remoteapp_access" {
  for_each = toset(local.customer_names_for_avd)

  scope                = module.avd.application_group_ids["ag-shared-lob-remoteapp"]
  role_definition_name = "Desktop Virtualization User"
  principal_id         = lookup(var.customer_avd_group_ids, each.key, "00000000-0000-0000-0000-000000000000")

  depends_on = [module.avd]
}
