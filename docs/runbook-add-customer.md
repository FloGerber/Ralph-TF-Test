# Runbook: Adding a New Customer

This runbook describes how to onboard a new customer onto the platform — either as a
**shared customer** (using the pooled RemoteApp host pool) or as a **dedicated customer**
(their own isolated Personal Desktop environment).

---

## Prerequisites

Before starting, you need:

- OpenTofu >= 1.6 installed
- Azure CLI authenticated with the OIDC service principal (or equivalent Contributor + RBAC Admin rights)
- The customer's **Azure AD / Entra ID Object ID** for their user group
- The customer name (lowercase, alphanumeric, max 8 chars recommended — used in resource names)
- `backend.hcl` populated with state backend coordinates

---

## Option A: Adding a Shared Customer

Shared customers use the pooled Windows 11 multi-session host pool and receive RemoteApp
applications. Multiple customers share the same session hosts.

### 1. Identify the customer's Entra group Object ID

```bash
az ad group show --group "<CustomerGroupName>" --query id -o tsv
# Example output: 00000000-0000-0000-0000-000000000001
```

### 2. Add the customer to `environments/shared/locals.tf`

Open `environments/shared/locals.tf` and add the new customer to the `customer_names` local:

```hcl
# Before:
customer_names = ["contoso", "fabrikam"]

# After:
customer_names = ["contoso", "fabrikam", "newcustomer"]
```

### 3. Add the customer's Entra group to `environments/shared/variables.tf` (or tfvars)

The `customer_avd_group_ids` variable maps customer name to their Entra group object ID:

```hcl
# environments/shared/terraform.tfvars  (or pass via -var)
customer_avd_group_ids = {
  contoso     = "00000000-0000-0000-0000-000000000001"
  fabrikam    = "00000000-0000-0000-0000-000000000002"
  newcustomer = "00000000-0000-0000-0000-000000000003"   # <-- add this
}

customer_principal_ids = {
  contoso     = "00000000-0000-0000-0000-000000000001"
  fabrikam    = "00000000-0000-0000-0000-000000000002"
  newcustomer = "00000000-0000-0000-0000-000000000003"   # <-- add this
}
```

### 4. Plan and review the changes

```bash
cd environments/shared
tofu init -backend-config=../../backend.hcl
tofu plan -var-file=terraform.tfvars
```

Expected new resources:

- `module.customer["newcustomer"].azurerm_resource_group.customer_rg` — Customer resource group
- `module.customer["newcustomer"].azurerm_role_assignment.customer_admins` — Admin RBAC on RG
- `module.customer["newcustomer"].azurerm_role_assignment.avd_user` — `Desktop Virtualization User` on RemoteApp app group
- `module.customer["newcustomer"].azurerm_role_assignment.fslogix_smb` — `Storage File Data SMB Share Contributor` on FSLogix storage
- `module.premium_storage["stfslogixnewcustomer"].azurerm_storage_account.this` — Per-customer FSLogix storage account
- `module.premium_storage["stfslogixnewcustomer"].azurerm_storage_share.this["profiles"]` — Profile container share
- `module.premium_storage["stfslogixnewcustomer"].azurerm_storage_share.this["office"]` — Office container share
- `module.premium_storage["stfslogixnewcustomer"].azurerm_private_endpoint.this` — Private endpoint for FSLogix

### 5. Apply the changes

```bash
tofu apply -var-file=terraform.tfvars
```

### 6. Configure FSLogix GPO for the new customer

FSLogix profile container settings cannot be fully managed via Terraform. After apply:

1. Log into a management VM with RSAT and GPMC installed.
2. Open Group Policy Management and create a new GPO named `GPO-FSLogix-<CustomerName>`.
3. Under `Computer Configuration > Policies > Administrative Templates > FSLogix > Profile Containers`:
   - **Enabled**: `1`
   - **VHD Location**: `\\<storageaccount>.file.core.windows.net\profiles`
4. Link the GPO to the OU containing the customer's session host computer accounts.

The storage account FQDN is available from the Terraform output:

```bash
tofu output premium_storage_private_endpoint_fqdns
```

### 7. Verify onboarding

- The customer's Entra group members should now be able to sign into AVD and launch the LoB application.
- FSLogix profiles will be created in the Premium Files share on first login.

---

## Option B: Adding a Dedicated Customer

Dedicated customers get their own isolated Personal Desktop environment: dedicated VNet,
dedicated session host VMSS, dedicated FSLogix storage, and a dedicated host pool.

### 1. Identify the customer's Entra group Object ID (as above)

### 2. Add a new module block to `environments/dedicated/customer-example.tf`

Copy the existing example block and customise:

```hcl
module "dedicated_customer_newcustomer" {
  source = "../../modules/dedicated"

  customer_name = "newcustomer"
  location      = "eastus"
  environment   = "prod"
  user_count    = 20       # Drives session host VMSS size (min 1, max 4 instances)

  # Hub connectivity (from networking/hub-and-spoke outputs)
  hub_vnet_id             = "<hub-vnet-resource-id>"
  hub_vnet_name           = "vnet-hub-prod"
  hub_firewall_private_ip = "<firewall-private-ip>"
  aadds_dns_servers       = ["10.0.5.4", "10.0.5.5"]

  # AVD image (from imaging/image-builder output)
  avd_image_id = "<shared-image-gallery-image-id>"

  # Domain join
  domain_join_config = {
    domain_name           = "avdshared.local"
    domain_username       = "domainadmin@avdshared.local"
    domain_password       = var.domain_join_password   # pass via -var or Key Vault
    ou_path               = "OU=NewCustomer,DC=avdshared,DC=local"
  }

  # FSLogix
  fslogix_config = {
    enabled             = true
    storage_account_key = ""   # Leave empty — access is via RBAC, not key
    profile_share_name  = "profiles"
  }

  # Private DNS zone for FSLogix private endpoints
  private_dns_zone_file_id = "<privatelink.file.core.windows.net-zone-resource-id>"

  # FSLogix RBAC — session host managed identity gets SMB Contributor
  fslogix_rbac_principal_id = ""   # Populated automatically from session host identity output

  tags = {
    Customer    = "newcustomer"
    Environment = "prod"
    ManagedBy   = "OpenTofu"
  }
}
```

> **Important**: The hub VNet ID, firewall IP, AADDS DNS IPs, and private DNS zone ID must
> come from the outputs of the networking layer. Retrieve them before running this apply:

```bash
cd networking/hub-and-spoke
tofu output hub_vnet_id
tofu output firewall_private_ip
tofu output private_dns_zone_ids
```

And from the shared environment:

```bash
cd environments/shared
tofu output aadds_domain_controller_ips
```

### 3. Plan and review the changes

```bash
cd environments/dedicated
tofu init -backend-config=../../backend.hcl
tofu plan
```

Expected new resources (approximately 25–35 resources):

- Resource group: `rg-newcustomer-prod`
- VNet + subnets + NSG in the dedicated address space
- VNet peering (spoke-to-hub + hub-to-spoke reverse)
- Route table with default route to hub firewall
- Azure Firewall (Standard, inside the dedicated module)
- Premium FileStorage account for FSLogix + file shares
- Private endpoint for FSLogix + DNS A-record
- AVD host pool (Personal, DepthFirst), workspace, Desktop app group
- Flexible VMSS with user-assigned managed identity
- DSC extension (host pool registration) + Domain Join extension
- `Storage File Data SMB Share Contributor` role assignment for VMSS identity

### 4. Apply the changes

```bash
tofu apply
```

### 5. Create the customer's OU in AADDS

Session hosts domain-join into a dedicated OU to keep GPO scope isolated:

```powershell
# Run on a management VM joined to avdshared.local
Import-Module ActiveDirectory
New-ADOrganizationalUnit -Name "NewCustomer" -Path "DC=avdshared,DC=local"
New-ADOrganizationalUnit -Name "SessionHosts" -Path "OU=NewCustomer,DC=avdshared,DC=local"
New-ADOrganizationalUnit -Name "Users" -Path "OU=NewCustomer,DC=avdshared,DC=local"
```

### 6. Assign users to the host pool

```bash
# Grant the customer's group access to the Desktop app group
az role assignment create \
  --assignee "<customer-group-object-id>" \
  --role "Desktop Virtualization User" \
  --scope "<desktop-app-group-resource-id>"
```

The desktop app group resource ID is available from:

```bash
cd environments/dedicated
tofu output -json | jq '.dedicated_customer_newcustomer_app_group_id'
```

### 7. Configure FSLogix GPO for the dedicated customer

As in Option A Step 6, create a GPO scoped to the customer's session host OU.
The FSLogix storage account FQDN:

```bash
cd environments/dedicated
tofu output -json | jq '.dedicated_customer_newcustomer_fslogix_fqdn'
```

---

## Post-Onboarding Verification Checklist

- [ ] Customer's Entra group appears in the AVD app group role assignments
- [ ] FSLogix storage account has a private endpoint with a DNS A-record in `privatelink.file.core.windows.net`
- [ ] Session hosts register successfully in the host pool (check AVD portal → Host Pools → Session Hosts)
- [ ] A test user from the customer's group can log in and receives a FSLogix profile container
- [ ] Profile VHD is created in the FSLogix file share (`\\<account>.file.core.windows.net\profiles\<upn>`)
- [ ] No direct public access to the FSLogix storage account (verify in Azure Portal → Networking → Public access: Disabled)

---

## Removing a Customer

### Shared customer removal

1. Remove the customer from `customer_names` in `environments/shared/locals.tf`
2. Remove the customer from `customer_avd_group_ids` and `customer_principal_ids` variables
3. Run `tofu plan` to confirm only customer resources are marked for destruction
4. Run `tofu apply`

> **Data retention**: The FSLogix Premium File Share and all profile VHDs will be destroyed.
> Export or back up profile data before removing the customer if required.

### Dedicated customer removal

1. Remove the `module "dedicated_customer_<name>"` block from `customer-example.tf`
2. Run `tofu plan` — all resources scoped to that module will be marked for destruction
3. Run `tofu apply`
