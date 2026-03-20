# Architecture Decision Records

This document captures significant architectural decisions made during the design and
implementation of the AVD platform. Each entry records the context, the decision, and
the rationale. Decisions are listed chronologically.

---

## ADR-001: Shared Pool Delivers RemoteApp Only (No Full Desktop)

**Date**: 2026-03-18
**Status**: Accepted

### Context

The shared host pool serves multiple customers simultaneously on the same set of session
hosts (Pooled / BreadthFirst assignment). Two application group types are possible:
- `Desktop`: exposes a full Windows desktop session
- `RemoteApp` (`RailApplications`): publishes individual applications (streamed as windows)

### Decision

The shared pool uses `preferred_app_group_type = "RailApplications"`. Only a single
RemoteApp application group (`ag-shared-lob-remoteapp`) is created for the shared host pool.
No Desktop application group is created for the shared pool.

### Rationale

- **Session density**: RemoteApp sessions consume significantly less memory and CPU than full
  desktop sessions (no desktop shell, Explorer, or background processes). A single session host
  can support 2–3× more concurrent RemoteApp users than full desktop users.
- **Multi-tenant isolation**: Publishing specific applications prevents customers from accessing
  each other's data. Full desktop access would expose the shared file system and create a larger
  lateral movement surface.
- **Customer requirement**: The customers served by the shared pool (`contoso`, `fabrikam`) require
  access to a single LoB web application, not a full persistent Windows environment. Customers
  requiring full desktops are served by the dedicated environment (see ADR-002).

### Consequences

- Customers on the shared pool cannot access a full Windows desktop.
- Applications must be published individually via `azurerm_virtual_desktop_application`.
- Customers requiring full desktop access must be provisioned on a dedicated environment.

---

## ADR-002: Flexible VMSS for All Session Hosts

**Date**: 2026-03-18
**Status**: Accepted

### Context

Azure Virtual Machine Scale Sets have two orchestration modes:
- **Uniform**: Classic VMSS (`azurerm_linux/windows_virtual_machine_scale_set`) — homogeneous
  instances, limited to 1000 VMs, tied to a single availability zone or fault domain configuration.
- **Flexible** (`azurerm_orchestrated_virtual_machine_scale_set`): Heterogeneous instances,
  supports up to 1000 VMs across Availability Zones, supports Gen2 VMs and Trusted Launch.

### Decision

All session host deployments use `azurerm_orchestrated_virtual_machine_scale_set`
(Flexible Orchestration mode).

### Rationale

- **Gen2 + Trusted Launch**: The Windows 11 multi-session SKU requires Hyper-V Generation 2 VMs.
  Flexible VMSS is required for Gen2 support. Trusted Launch (Secure Boot + vTPM) is a Microsoft
  security recommendation for AVD session hosts and is only available on Gen2 VMs.
- **Availability Zone spreading**: Flexible VMSS supports spreading instances across 3 Availability
  Zones in a single VMSS resource, providing zone-level HA without managing multiple VMSS resources.
- **Future extensibility**: Microsoft is investing in Flexible orchestration as the forward path for
  VMSS. Uniform mode does not support all new VM capabilities.

### Consequences

- **Inline extensions only**: `azurerm_virtual_machine_scale_set_extension` resources are not
  compatible with Flexible VMSS. All extensions (DSC host pool registration, domain join) must be
  declared as inline `extension {}` blocks inside the VMSS resource.
- **UserAssigned identity only**: The `identity` block on Flexible VMSS only supports
  `type = "UserAssigned"`. A separate `azurerm_user_assigned_identity` resource is required.
  This is a known Azure API limitation.
- **Admin password management**: Since no `admin_password` input is accepted from callers, a
  `random_password` resource is generated per VMSS within the module. The password is stored in
  Terraform state (encrypted at rest in the Azure Blob Storage backend).

---

## ADR-003: AADDS Deployed in Hub VNet

**Date**: 2026-03-18
**Status**: Accepted

### Context

Session hosts require domain membership for FSLogix profile container authentication (Kerberos)
and Group Policy delivery. Options considered:

1. **Azure AD Join (AAD-only)**: No on-premises AD dependency; uses Entra ID credentials directly.
2. **Azure AD DS (AADDS)**: Microsoft-managed domain controllers in Azure; compatible with
   traditional AD features (Kerberos, NTLM, LDAP, GPO).
3. **Customer-managed AD on Azure VMs**: Full AD DS control; requires managing DC VMs, patching,
   and availability.

### Decision

Azure AD Domain Services (AADDS) is deployed in the hub VNet (`snet-aadds`, `10.0.5.0/24`) and
is accessible from all spoke VNets via peering.

### Rationale

- **Centralised**: A single AADDS instance in the hub serves both the shared and dedicated spokes
  without replication. No per-spoke AD infrastructure is needed.
- **Managed service**: Microsoft manages DC availability, patching, and replication. No VM
  maintenance burden.
- **FSLogix compatibility**: FSLogix profile containers require Kerberos authentication to Azure
  Files SMB shares. AADDS provides the Kerberos tickets needed for SMB authentication via
  `Storage File Data SMB Share Contributor` RBAC assignments.
- **GPO support**: AADDS supports Group Policy Objects, enabling FSLogix profile container
  configuration and other machine policies.

### Consequences

- **Two-pass deployment**: AADDS domain controller IPs are only known after the AADDS resource
  is provisioned (~45–60 min). The networking layer must be applied once without DNS servers,
  then re-applied after AADDS to inject the IPs into spoke VNet DNS server settings.
- **AADDS subnet NSG**: The AADDS subnet NSG must allow Microsoft management traffic (TCP 443,
  TCP 5986) from the `AzureActiveDirectoryDomainServices` service tag. These rules are declared
  explicitly to prevent state drift (Microsoft injects them automatically but Terraform detects drift).
- **AADDS provisioning time**: First-time AADDS provisioning takes 45–60 minutes. Plan accordingly.
- **GPO management is out-of-band**: Terraform cannot manage AD Group Policy Objects. The
  `null_resource.gpo_config` in `modules/aadds` tracks GPO intent as code comments; actual
  GPO configuration must be applied via PowerShell (GPMC) on a management VM joined to the domain.

---

## ADR-004: FSLogix via Azure Premium Files with Private Endpoints

**Date**: 2026-03-18
**Status**: Accepted

### Context

FSLogix profile containers require an SMB file share. Options:

1. **Azure Files Standard (ZRS)**: Lower cost; suitable for light workloads.
2. **Azure Files Premium (ZRS)**: Higher IOPS; lower latency; uses FileStorage kind.
3. **Azure NetApp Files**: Highest performance; higher cost and complexity.
4. **Storage Spaces Direct on session hosts**: Local storage; no profile portability.

### Decision

Each customer receives a dedicated **Azure Files Premium (ZRS)** storage account with private
endpoints registered in the `privatelink.file.core.windows.net` Private DNS Zone.

### Rationale

- **Performance**: Premium Files provides consistent sub-millisecond latency on profile mounts,
  which directly impacts user login time. Standard Files can cause login delays of 5–30 seconds
  under concurrent load.
- **Per-customer isolation**: A dedicated storage account per customer ensures one customer's
  profile load cannot impact another customer's storage performance or access their data.
- **Security**: `public_network_access_enabled = false` on all storage accounts. All access is
  exclusively via private endpoints. No data traverses the public internet.
- **Zone redundancy**: `ZRS` provides zone-level resilience within a single Azure region at lower
  cost than `GRS`. Given that AADDS and session hosts are also zone-redundant, this provides a
  consistent HA tier.

### Consequences

- **FileStorage kind limitation**: Premium FileStorage accounts use `account_kind = "FileStorage"`.
  This means blob storage (`subresource_names = ["blob"]`) is not supported — only `["file"]` is
  valid for private endpoints on these accounts.
- **CKV_AZURE_206 Checkov check**: This check only accepts GRS/RAGRS/GZRS/RAGZRS as compliant
  replication types. ZRS fails this check despite being zone-redundant. Inline `#checkov:skip`
  annotations are used with documented justification.
- **Private DNS Zone required**: Without `azurerm_private_dns_zone_group` inside the private
  endpoint resource, Azure does NOT automatically register the A-record. The DNS zone group block
  is mandatory.

---

## ADR-005: Checkov Dual Integration (Pre-commit + GitHub Actions CI)

**Date**: 2026-03-19
**Status**: Accepted

### Context

IaC security scanning can be enforced at different points in the development workflow:
- **Pre-commit hooks**: Catch issues before code is committed (shift-left).
- **CI pipeline**: Enforce scanning on every pull request/push (gate before merge).
- **Ad-hoc**: Run manually as needed.

### Decision

Checkov is integrated at both levels:

1. **Pre-commit hook** (`.pre-commit-config.yaml`): Runs `checkov --framework terraform --compact
   --quiet --config-file checkov-config.yaml` on every `git commit`.
2. **GitHub Actions CI** (`.github/workflows/checkov.yml`): Runs on every push and pull request
   to `main`. Uploads a JSON report as a workflow artefact (retained 30 days).

### Rationale

- **Shift-left**: Pre-commit hooks catch issues at the developer workstation before code reaches
  the repository. This reduces PR review cycles and prevents security regressions reaching CI.
- **CI gate**: The CI pipeline provides a second enforcement layer for contributors who bypass
  pre-commit hooks (e.g., `git commit --no-verify`). The CI gate is mandatory; the pre-commit
  hook is advisory.
- **Framework flag**: The correct Checkov framework flag for OpenTofu/Terraform HCL is
  `--framework terraform`. The `--framework opentofu` value is not valid and causes an error.
- **Zero unsuppressed failures**: The policy is zero unsuppressed critical/high findings in CI.
  Any suppression must have an inline `#checkov:skip=<CHECK_ID>:<JUSTIFICATION>` comment inside
  the resource block and a corresponding entry in the CHECKOV.md suppressions register.

### Consequences

- All contributors must install `pre-commit` and `checkov` locally (`pip install pre-commit checkov`).
- New resources that introduce Checkov findings require either a fix or a documented suppression
  before the PR can be merged.
- The `--framework terraform` flag must be used in all scripts, CI steps, and documentation.
  The `--framework opentofu` value does not exist.

---

## ADR-006: Environment Layers as Independent Root Modules (Not Child Modules)

**Date**: 2026-03-18
**Status**: Accepted

### Context

OpenTofu/Terraform supports two approaches to structuring multi-environment deployments:
1. **Single root + child modules**: One `main.tf` at the root calls sub-directories as modules.
2. **Multiple independent root modules**: Each environment directory is its own root with
   `terraform {}` and `backend {}` blocks, deployed independently.

### Decision

Each deployable unit (`bootstrap/`, `networking/hub-and-spoke/`, `imaging/image-builder/`,
`environments/shared/`, `environments/dedicated/`) is an independent root module with its
own `terraform { backend "azurerm" {} }` block and `backend.hcl` file.

### Rationale

- **Backend isolation**: Directories containing `backend {}` blocks cannot be called as child
  modules. Attempting to do so causes OpenTofu to refuse the call. This is a hard constraint.
- **Blast radius**: Independent state files limit the blast radius of a failed `apply`. A broken
  shared environment apply cannot corrupt the networking layer state.
- **Parallelism**: Teams can deploy the image builder independently of the environments, and
  the networking layer can be updated without re-deploying AVD control plane resources.
- **State visibility**: Each root's `tofu state list` shows only resources for that layer,
  making state debugging and targeted `tofu import` or `tofu state mv` operations simpler.

### Consequences

- **No cross-module data sources in the same codebase**: Outputs from one root module cannot
  be consumed directly by another using `module.networking.outputs.*`. Data must be passed
  manually (copy output values into variables) or via `terraform_remote_state` data sources.
- **Deployment order must be documented**: Operators must follow the documented deployment order
  (bootstrap → networking → imaging → shared → dedicated) to satisfy inter-layer dependencies.
- **OpenTofu workspaces not used**: Named workspaces (`tofu workspace new`) are not used in
  this project. State isolation is achieved via distinct `key` values in each layer's backend
  configuration.

---

## ADR-007: Azure Image Builder with PlatformImage Source

**Date**: 2026-03-19
**Status**: Accepted

### Context

Azure Image Builder image templates support multiple source types:
- `PlatformImage`: Builds from an Azure Marketplace image (publisher/offer/sku/version).
- `ImageVersion`: Builds from an existing Shared Image Gallery image version.
- `ManagedImage`: Builds from an existing managed image resource.

### Decision

The image template uses `type = "PlatformImage"` with `MicrosoftWindowsDesktop/windows-11/win11-23h2-avd/latest`.

### Rationale

- **Gen2 + Trusted Launch**: The `win11-23h2-avd` SKU from Azure Marketplace is a Gen2,
  Trusted Launch-compatible image. Using `PlatformImage` directly targets this without
  requiring a pre-existing gallery version.
- **No circular dependency**: Using `ImageVersion` would require a pre-built gallery image to
  exist before the first build — a chicken-and-egg problem on initial deployment.
- **Always-current base**: `version = "latest"` automatically picks up the most recent patched
  base image from the marketplace on each build, reducing the need for separate Windows Update
  customisation steps.

### Consequences

- The `azurerm_shared_image` gallery image definition must have `hyper_v_generation = "V2"`
  and `trusted_launch_enabled = true` to match the Gen2 + Trusted Launch source image.
- The `source_image_id` variable (used for `ImageVersion` source) has been removed from
  `imaging/image-builder/variables.tf`. It is replaced by `source_image_publisher`,
  `source_image_offer`, `source_image_sku`, and `source_image_version`.

---

## ADR-008: GPO Configuration via null_resource (Out-of-Band)

**Date**: 2026-03-18
**Status**: Accepted

### Context

FSLogix profile container registry keys and domain computer policies are most reliably
configured via Active Directory Group Policy Objects. The `azurerm_active_directory_domain_service_group_policy`
resource was used in an earlier version of the code.

### Decision

GPO configuration is tracked as `null_resource` blocks in `modules/aadds/main.tf` with
PowerShell examples in comments. Actual GPO application is performed out-of-band via GPMC
or `Set-GPRegistryValue` on a management VM joined to the AADDS domain.

### Rationale

- **Resource does not exist**: `azurerm_active_directory_domain_service_group_policy` is not
  a real resource in the `azurerm` provider 4.x. The OpenTofu registry returns 404 for this
  resource type. Any code using it will fail at `tofu validate`.
- **API limitation**: The Azure AADDS API does not expose GPO management endpoints. GPOs in
  AADDS are managed via the standard AD GPMC tooling, not the Azure Resource Manager API.
- **Code as documentation**: The `null_resource.gpo_config` with `triggers` capturing the
  intended configuration values serves as machine-readable documentation of the GPO intent,
  even though it cannot apply the changes itself.

### Consequences

- GPO configuration is an out-of-band operational step. It must be performed after AADDS is
  provisioned and the management VM is available.
- The `docs/runbook-add-customer.md` includes the PowerShell commands for GPO setup.
- Checkov and tflint do not scan the PowerShell content in comments.

---

## ADR-009: AVD Registration Token — 2-Hour Rolling Window

**Date**: 2026-03-20
**Status**: Accepted

### Context

The AVD host pool registration token is used by session hosts to register themselves with a host
pool during provisioning. A token with a long or permanent expiry (e.g., `2027-12-31`) poses a
significant security risk: if the token is leaked (e.g., in a plan output, log, or state file),
an attacker can register unauthorised session hosts into the host pool for years.

### Decision

`azurerm_virtual_desktop_host_pool_registration_info.this` uses:

```hcl
expiration_date = timeadd(timestamp(), "2h")
```

The token is valid for exactly **2 hours from the time of `tofu apply`**. This is regenerated on
every pipeline run. The `RegistrationInfoToken` is passed exclusively via `protected_settings`
(not `settings`) in the DSC extension to prevent exposure in plan output.

The resource also declares:

```hcl
lifecycle {
  replace_triggered_by = [azurerm_virtual_desktop_host_pool.this]
}
```

This ensures the registration token is regenerated whenever the host pool itself is replaced.

### Rationale

- **Least-privilege token lifetime**: A 2-hour window is sufficient for a pipeline run to complete
  session host registration. It severely limits the usefulness of a leaked token.
- **`timeadd(timestamp(), "2h")` pattern**: `timestamp()` returns the current UTC time at plan
  time; `timeadd` adds a duration string. This is the idiomatic OpenTofu/Terraform approach for
  rolling expiry windows on registration resources.
- **`protected_settings` for token**: Extension `protected_settings` are encrypted at rest and
  are not shown in plan output. Placing the token in plain `settings` would expose it in every
  `tofu plan` output and in the state file in plaintext.

### Consequences

- **"replace" on every `tofu plan`**: Because `timestamp()` is re-evaluated at plan time, the
  `expiration_date` will always differ from the stored state value. OpenTofu will show the
  `azurerm_virtual_desktop_host_pool_registration_info` resource as requiring replacement on
  every plan. **This is expected and by design.** It is not a bug or a misconfiguration.
- **Pipeline must run `apply` to keep tokens valid**: If a session host is provisioned more than
  2 hours after the last `tofu apply`, registration will fail. Pipelines that provision new
  hosts must run `tofu apply` immediately before or during provisioning.
- **Token not visible in plan output**: Operators cannot retrieve the token from `tofu plan`
  output. The token is available in the Terraform state and via the Azure Portal.

---

## ADR-010: Azure Firewall DNS Proxy for AADDS DNS Forwarding

**Date**: 2026-03-20
**Status**: Accepted

### Context

Session hosts in the shared and dedicated spokes must resolve both Azure Private DNS zones and the
managed AADDS domain. Azure Firewall sits centrally in the hub and is the natural DNS forwarder for
spokes, but it only forwards DNS queries when Firewall Policy DNS proxy is enabled and configured
with upstream DNS servers.

AADDS domain controller IPs are not known until the managed domain finishes provisioning, which means
the networking layer cannot be fully wired for DNS on the first apply.

### Decision

The hub Azure Firewall Policy enables DNS proxy and points upstream DNS to `var.aadds_dns_server_ips`:

```hcl
dns {
  proxy_enabled = true
  servers       = length(var.aadds_dns_server_ips) > 0 ? var.aadds_dns_server_ips : []
}
```

Deployments follow a two-pass process:

1. First apply `networking/hub-and-spoke` with `aadds_dns_server_ips = []`.
2. Provision AADDS and capture the domain controller IPs.
3. Re-apply `networking/hub-and-spoke` with the actual AADDS DNS IPs.

### Rationale

- **Central DNS forwarding**: Azure Firewall DNS proxy gives all spokes a single DNS forwarder in the
  hub while still allowing upstream resolution through AADDS domain controllers.
- **Private DNS + domain join compatibility**: Session hosts need both private endpoint name
  resolution and managed domain resolution. Enabling DNS proxy makes the firewall the shared path for
  those lookups.
- **Safe first deployment**: Using an empty list on the first apply avoids blocking the initial hub
  deployment on AADDS' long provisioning time.

### Consequences

- The first `tofu apply` for `networking/hub-and-spoke` intentionally runs with no AADDS DNS server
  IPs configured.
- A second apply is mandatory after AADDS finishes provisioning so the firewall policy and spoke VNet
  DNS settings receive the actual domain controller IPs.
- Consumers can use the exported firewall private IP to point downstream DNS clients or route tables
  at the hub firewall consistently.
