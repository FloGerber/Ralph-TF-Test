FSLogix Storage Architecture

This document captures the approved FSLogix storage pattern used by both the
shared and dedicated landing zones. It specifies storage choices, identity and
RBAC mapping, network access, NTFS/SMB ACL considerations, and host configuration
(GPO) needed to ensure predictable, isolated, and high-performance FSLogix
profile containers.

1) Storage pattern
- Azure Files Premium (FileStorage) is required for FSLogix profile containers.
- One FSLogix profile share per customer. The repository implements this as one
  FileStorage account (kind=FileStorage) and a `profiles` file share per
  customer in the shared model, and the same pattern is used for dedicated
  landing zones.
- Module reference: `modules/fslogix` provisions `azurerm_storage_account` with
  `account_kind = "FileStorage"` and creates per-share `azurerm_storage_share`.
  Callers should set `enable_premium_storage = true` (default) to ensure the
  Premium tier is used. Example invocations live in
  `environments/shared/locals.tf` and `modules/dedicated/main.tf`.

2) Identity and authentication
- FSLogix relies on SMB and requires domain authentication that supports
  Kerberos/NTLM. The platform uses Azure Active Directory Domain Services
  (AADDS) or hybrid AD DS for this purpose; plain Azure AD-only accounts are
  insufficient.
- Create one Entra/AAD group per customer for FSLogix access (naming: `cust-<customer>-fslogix`).
- File share NTFS/SMB ACLs are applied against AADDS identities (computer or
  group accounts) so that group-based membership controls access to the
  customer's profile share.

3) RBAC and service principals
- Management/RBAC model:
  - Assign `Storage File Data SMB Share Contributor` on the storage account or
    individual share to the principal that needs SMB/SMB-ACL management.
    Typical principals:
      * The AADDS computer account or converted Entra group used by session hosts
      * CI/CD identities that provision or rotate storage keys (when used)
  - Session host managed identities (VMSS identities) must be granted
    `Storage File Data SMB Share Contributor` (or equivalent) against the
    target storage account so hosts can mount using identity-based access.
- Terraform mapping: `modules/avd` consumes a `fslogix_storage_account_ids`
  input and creates role assignments for session hosts (see
  `modules/avd/main.tf`). Per-customer role assignment examples are present in
  `environments/shared/locals.tf`.

4) NTFS/SMB ACLs and share layout
- Maintain one `profiles` share per customer. Put optional Office/Container
  shares on the same account if desired, but profile isolation requires one
  top-level profiles share per customer.
- Apply NTFS/SMB ACLs to the share and container roots using AADDS identities
  (the per-customer Entra group or computer account). This prevents cross-customer
  access even when the underlying storage account is shared across multiple
  objects.

5) Network access patterns
- Private endpoints: create a private endpoint for each FileStorage account and
  place them in a dedicated storage subnet (example: `snet-shared-storage` in
  `environments/shared`). Private DNS zones should be registered in the hub
  Private DNS zone to resolve storage account FQDNs from session hosts.
- Storage account network rules: default deny when private endpoints are used
  (module sets `public_network_access_enabled = false` and `default_action = "Deny"`).
- Use service endpoints sparingly; prefer private endpoints for secure,
  cross-subnet access from session hosts and image-builder pipelines.

6) Host configuration (GPO / ADMX settings)
- FSLogix agent registry keys and GPO settings must be applied to session hosts
  (Windows):
  - HKLM:\SOFTWARE\FSLogix\Profiles\Enabled = 1 (DWORD)
  - HKLM:\SOFTWARE\FSLogix\Profiles\VHDLocations = MultiString with the
    UNC path(s) for the customer's share, e.g.
    \\\stfslogixcontoso.file.core.windows.net\\profiles
  - HKLM:\SOFTWARE\FSLogix\Profiles\VHDType = "vhdx" (recommended)
  - Configure `DeleteLocalProfileWhenVHDNotAttached` and `Concurrent` settings
    per performance requirements (refer to FSLogix documentation for tuning)
- Distribute settings via Group Policy (ADMX) when using AADDS/hybrid AD DS.
  The imaging pipeline (`imaging/image-builder`) includes example registry
  steps to install and set FSLogix keys; in production use GPO for manageability.

7) Operational notes and security
- Storage keys should not be long-lived in repository files. Use Key Vault for
  any secrets and prefer managed identity/SMB identity-based mount patterns when
  possible.
- Backups/retention: Premium FileStorage supports snapshots—define an
  operational backup policy for profile shares as required by SLAs.
- Monitoring: enable diagnostic settings for storage accounts and route to the
  platform Log Analytics workspace (modules include `modules/monitoring`).

8) Where the pattern is referenced
- Shared landing zone: `environments/shared` constructs per-customer
  Premium FileStorage accounts and `profiles` shares and wires RBAC via
  `modules/customer` (see `environments/shared/locals.tf`).
- Dedicated landing zone: `modules/dedicated` creates a per-customer
  FileStorage account and `profiles` share when invoked from
  `environments/dedicated/customer-example.tf`.

9) Quick checklist for onboarding a customer
 - Create Entra group `cust-<customer>-fslogix` (used for NTFS/SMB ACLs).
 - Ensure AADDS or hybrid AD DS is available and session hosts are domain joined.
 - Create storage account (Premium FileStorage) and `profiles` share (modules
   perform this automatically when using onboarding manifests).
 - Create private endpoint in the storage subnet and register private DNS.
 - Assign `Storage File Data SMB Share Contributor` to the session host
   managed identity and to any admin identity that needs to manage SMB ACLs.
 - Apply FSLogix GPO/registry settings to session hosts with the correct
   `VHDLocations` UNC path and enable the FSLogix agent.

References: `modules/fslogix/main.tf`, `environments/shared/locals.tf`,
`modules/dedicated/main.tf`, `modules/avd/main.tf`, `docs/identity.md`.
