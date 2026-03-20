# PRD: Azure Virtual Desktop Multi-Tenant Environment with OpenTofu (v2)

## Overview

Build a production-grade Azure Virtual Desktop (AVD) environment supporting both shared multi-tenant hosting (RemoteApp application delivery — no full Desktop) and dedicated single-tenant deployments. The solution follows Azure Landing Zone and Cloud Adoption Framework principles, aligns with the Microsoft Well-Architected Framework, and is fully automated using OpenTofu with modular, DRY configurations. The environment serves multiple customers with a custom Line of Business (LoB) application, provides optional isolation through dedicated AVD environments, and uses Hub-and-Spoke networking with Azure Firewall, Private DNS, Entra Domain Services (AADDS), FSLogix, Azure Image Builder (Flexible VMSS session hosts), and comprehensive Checkov security scanning via both local pre-commit hooks and CI pipelines.

Key decisions captured from architecture sessions:
- **Shared pool:** RemoteApp-only host pool (no Published Desktop), customers share session hosts, per-customer application group assignments control access
- **AADDS:** Single shared instance in the hub, peered to all spokes
- **Hub:** Azure Firewall + Private DNS Zones for all private endpoints
- **Session hosts:** Migrate from classic VMSS (`azurerm_virtual_machine_scale_set`) to Flexible VMSS (`azurerm_orchestrated_virtual_machine_scale_set`) with AVD extension
- **App Attach:** Design for flexibility (MSIX or new App Attach), delivery mechanism selectable via variable
- **Bootstrap:** Provisions state backend + Hub VNet + Azure Firewall (full platform landing zone)
- **Checkov:** Local pre-commit hook + CI pipeline (GitHub Actions or Azure DevOps)
- **Platform team only** manages all environments (no customer self-service)

## Quality Gates

These commands must pass for every user story:
- `tofu fmt -check` — OpenTofu format validation
- `tofu validate` — OpenTofu configuration validation
- `tofu plan` — Dry-run plan must complete without errors (use `-var-file=terraform.tfvars` where applicable)
- `checkov -d . --framework opentofu --compact` — Security and misconfiguration scanning (0 critical/high findings or documented suppressions)
- `tflint --recursive` — Linting for deprecated syntax, unused variables, and best practices

For infrastructure stories that touch networking, storage, or identity:
- Verify Checkov passes with no `CKV_AZURE_*` critical findings
- Verify `tofu validate` succeeds within both `bootstrap/` and root module contexts

## User Stories

---

### US-001: Extend bootstrap to provision full platform landing zone

**Description:** As a platform operator, I want the bootstrap layer to provision the state backend, Hub VNet with Azure Firewall, Private DNS Zones, management groups, and Log Analytics in a single `tofu apply`, so that the platform foundation is ready before any workload is deployed.

**Acceptance Criteria:**
- [ ] `bootstrap/main.tf` provisions: resource group, state storage account + container (already exists), management groups (`Landing Zones`, `Management`, `Connectivity`, `Shared`, `Dedicated`), Azure Policy (`CostCenter` tag audit)
- [ ] `bootstrap/main.tf` provisions: Hub VNet (`10.0.0.0/16`), subnets `GatewaySubnet`, `AzureFirewallSubnet`, `snet-management`, `snet-frontend`, `snet-backend`
- [ ] Azure Firewall (Standard SKU) with Firewall Policy (threat intel: Deny, IDS: Deny) deployed in hub
- [ ] Private DNS Zones for `privatelink.file.core.windows.net` and `privatelink.blob.core.windows.net` created and linked to hub VNet
- [ ] Log Analytics workspace `law-bootstrap-<env>` provisioned (already exists, verify correct retention)
- [ ] Microsoft Defender for Cloud enabled for `VirtualMachines` (already exists)
- [ ] OIDC service principal guidance documented in `BACKEND.md` — bootstrap outputs the required Service Principal app ID and required role assignments
- [ ] All state backend outputs remain backward-compatible (no breaking changes)
- [ ] `bootstrap/` passes all quality gates

---

### US-002: Refactor Hub-and-Spoke networking into a standalone platform layer

**Description:** As a platform engineer, I want the Hub-and-Spoke networking code moved into its own deployable root module under `networking/hub-and-spoke/` so that it can be versioned, planned, and applied independently from workloads.

**Acceptance Criteria:**
- [ ] `networking/hub-and-spoke/main.tf` manages all hub and static spoke VNets as defined in the reference architecture (hub, shared spoke, dedicated spoke template)
- [ ] Hub-to-shared and hub-to-dedicated peerings are bidirectional (both directions in same module to avoid state split)
- [ ] Reverse peering resource `azurerm_virtual_network_peering.reverse` in `modules/networking/main.tf` is fixed — currently references `remote_vnet_id` as the `virtual_network_name`, causing a plan error; must reference the actual VNet name of the remote network
- [ ] `networking/hub-and-spoke/` has its own `backend.hcl` with state key `networking/hub-and-spoke`
- [ ] Outputs export: `hub_vnet_id`, `shared_spoke_vnet_id`, `dedicated_spoke_vnet_id`, `hub_firewall_private_ip`, `subnet_ids` (map)
- [ ] Private DNS Zone IDs exported for consumption by workload modules
- [ ] Module passes all quality gates; `networking/hub-and-spoke/README.md` updated

---

### US-003: Migrate session hosts from classic VMSS to Flexible VMSS (Orchestrated)

**Description:** As a platform engineer, I want session hosts to use `azurerm_orchestrated_virtual_machine_scale_set` (Flexible Orchestration mode) so that AVD extension support, rolling upgrades, and zone-redundancy follow Microsoft's recommended deployment model.

**Acceptance Criteria:**
- [ ] Remove `azurerm_virtual_machine_scale_set` (classic) resource from `modules/avd/main.tf`
- [ ] Add `azurerm_orchestrated_virtual_machine_scale_set` with: `platform_fault_domain_count = 1`, `single_placement_group = false`, `zones = ["1","2","3"]` (configurable)
- [ ] OS disk configured: `storage_account_type = "Premium_LRS"`, `disk_size_gb` variable-driven
- [ ] `os_profile` block uses `windows_configuration` sub-block (Flexible VMSS syntax)
- [ ] `SystemAssigned` managed identity retained
- [ ] AVD DSC extension (`Microsoft.PowerShell.DSC`) added as `azurerm_virtual_machine_scale_set_extension` for host pool registration — replaces the custom PowerShell token injection
- [ ] Domain join extension (`JsonADDomainExtension`) retained and chained after DSC extension via `provision_after_extensions`
- [ ] `var.session_host_config` schema updated: remove `admin_password` field (not supported in Flexible VMSS with managed identity); add `enable_automatic_os_upgrade`, `zones`
- [ ] `modules/dedicated/main.tf` `session_host_config` local updated to match new schema
- [ ] `modules/avd/variables.tf` and `modules/avd/outputs.tf` updated accordingly
- [ ] All existing dedicated and shared environment consumers remain functional (`tofu validate` passes in `environments/shared/` and `environments/dedicated/`)
- [ ] Passes all quality gates

---

### US-004: Configure shared RemoteApp-only host pool for multi-tenant LoB delivery

**Description:** As a platform operator, I want the shared AVD host pool configured as RemoteApp-only (no Published Desktop) with per-customer application groups, so that customers can only access the LoB application and not arbitrary desktop sessions.

**Acceptance Criteria:**
- [ ] Shared host pool type: `Pooled`, `preferred_app_group_type = "RailApplications"`, load balancing: `BreadthFirst`
- [ ] **No** `Desktop` application group created for the shared host pool
- [ ] `azurerm_virtual_desktop_application_group` created with `type = "RemoteApp"` for the LoB application
- [ ] `azurerm_virtual_desktop_application` resource created for the LoB application entry (name, path, command-line arguments as variables)
- [ ] Per-customer Entra group can be assigned to the shared RemoteApp application group via `azurerm_role_assignment` (`Desktop Virtualization User`)
- [ ] Scaling plan configured with at minimum: `Weekdays` schedule (ramp up 07:00, peak 09:00-18:00, ramp down 18:00, off-peak 20:00)
- [ ] `environments/shared/customer.tf` updated: each customer entry maps to a role assignment on the shared RemoteApp application group
- [ ] Workspace linked to RemoteApp application group
- [ ] `environments/shared/` passes all quality gates

---

### US-005: Implement per-customer Premium File Shares for FSLogix + App Attach

**Description:** As a platform architect, I want each customer to have a dedicated Azure Premium File Share for FSLogix profiles and a separate shared Premium File Share for App Attach packages, so that customer profile data is isolated and application delivery is centralized.

**Acceptance Criteria:**
- [ ] `modules/storage/main.tf`: private endpoint `subresource_names` corrected to `["file"]` only for FileStorage accounts (currently has `["blob", "file"]` which is invalid for FileStorage kind)
- [ ] Each customer in the shared environment gets: one `FileStorage` Premium storage account + one `profiles` file share (100 GiB minimum, Premium tier)
- [ ] One additional `FileStorage` Premium storage account in the shared spoke for App Attach: file share named `appattach` (configurable quota)
- [ ] The dedicated customer module (`modules/dedicated/`) already provisions per-customer FSLogix storage; verify it is consistent with above schema and add `appattach` share support via optional variable
- [ ] All FSLogix storage accounts: `https_traffic_only_enabled = true`, `min_tls_version = "TLS1_2"`, `allow_nested_items_to_be_public = false`, network rules default `Deny` with Private Endpoint
- [ ] Private endpoints for all file shares deployed into `snet-shared-storage` (shared) or `snet-dedicated-storage` (dedicated) — subnet must be added to dedicated spoke if missing
- [ ] Private DNS A-records registered in hub Private DNS Zone `privatelink.file.core.windows.net`
- [ ] RBAC: `Storage File Data SMB Share Contributor` assigned to AADDS computer accounts / Entra groups per customer
- [ ] Outputs expose storage account names, file share names, and private endpoint FQDNs
- [ ] Passes all quality gates

---

### US-006: Configure FSLogix profile containers via AADDS and Group Policy

**Description:** As a security architect, I want FSLogix profile containers configured through AADDS Group Policy Objects so that session hosts automatically mount user profile VHDs without manual configuration.

**Acceptance Criteria:**
- [ ] `modules/aadds/main.tf` resource `azurerm_active_directory_domain_service_group_policy` verified — check if this resource type exists in `azurerm ~> 4.0`; if it does not exist, replace with a `null_resource` + comment block that documents the required GPO settings and a `local-exec` provisioner using PowerShell/Azure CLI to set registry-equivalent settings via `azurerm_virtual_machine_extension`
- [ ] FSLogix registry keys documented/applied: `HKLM:\SOFTWARE\FSLogix\Profiles\Enabled = 1`, `VHDLocations = \\<storageaccount>.file.core.windows.net\profiles`, `DeleteLocalProfileWhenVHDShouldApply = 1`, `FlipFlopProfileDirectoryName = 1`
- [ ] AADDS deployed in hub resource group with subnet `snet-aadds` (10.0.5.0/24) — add this subnet to `networking/hub-and-spoke/main.tf`
- [ ] AADDS subnet NSG allows: TCP 636 (LDAPS), TCP/UDP 389 (LDAP), TCP/UDP 88 (Kerberos), TCP/UDP 53 (DNS) from spoke subnets
- [ ] AADDS DNS server IPs exported as outputs and injected into all spoke VNet DNS server settings
- [ ] `modules/aadds/variables.tf` adds `aadds_subnet_id` variable; removes dependency on non-existent `azurerm_resource_group.this` inside module (networking module already creates the RG)
- [ ] `modules/fslogix/main.tf` `virtual_network_subnet_ids` dynamic block syntax corrected — currently uses `content { subnet_id = ... }` which is invalid; use `virtual_network_subnet_ids = [var.subnet_id]` directly in the network rules resource
- [ ] Passes all quality gates

---

### US-007: Update Azure Image Builder pipeline for Flexible VMSS golden image

**Description:** As a platform engineer, I want the Image Builder pipeline updated so that the golden image produced is compatible with Flexible VMSS deployment and includes FSLogix configured for AADDS-joined profile paths.

**Acceptance Criteria:**
- [ ] `imaging/image-builder/main.tf`: image template `source` block changed from `"ImageVersion"` type to `"PlatformImage"` type with `publisher`, `offer`, `sku`, `version` variables — current `source_image_id` (ImageVersion) requires an existing gallery version; use platform image as base to avoid circular dependency
- [ ] Shared Image Gallery image definition updated: `hyper_v_generation = "V2"` (already correct), add `trusted_launch_enabled = true` for Flexible VMSS compatibility
- [ ] Image Builder customization steps: retain existing steps (Windows Update, Defender, Firewall, FSLogix, AVD optimizations); add step to configure FSLogix registry keys with placeholder profile path (`\\placeholder.file.core.windows.net\profiles`) — actual path set via GPO at runtime
- [ ] Remove Chocolatey-based installation of `DirectoryServices-DomainController` (wrong role for session hosts) — replace with correct step that installs `RSAT-AD-PowerShell` only if needed
- [ ] Add `sysprep` step at end of customize list (`type = "WindowsRestart"` + final `type = "PowerShell"` calling `sysprep.exe /generalize /oobe /shutdown /quiet`)
- [ ] `imaging/image-builder/variables.tf` adds: `source_image_publisher`, `source_image_offer`, `source_image_sku`, `source_image_version` (replaces `source_image_id`)
- [ ] `imaging/image-builder/outputs.tf` exports `gallery_image_id` and `image_template_name`
- [ ] `imaging/image-builder/` passes all quality gates

---

### US-008: Implement Checkov integration (pre-commit + CI pipeline)

**Description:** As a security engineer, I want Checkov scanning integrated into both local pre-commit hooks and a CI pipeline so that all OpenTofu configurations are validated for security misconfigurations before merge and before deployment.

**Acceptance Criteria:**
- [ ] `.pre-commit-config.yaml` created at repo root with: `checkov` hook (`bridgecrew/checkov`) targeting `--framework terraform` with `--compact --quiet`; `tofu fmt` hook; `tflint` hook
- [ ] `checkov-config.yaml` (or `.checkov.yaml`) created with: `framework: terraform`, `output: cli,json`, `output-file-path: reports/checkov`, `skip-check: []` (document any suppressions inline with `#checkov:skip=` comments in `.tf` files, not blanket skips in config)
- [ ] GitHub Actions workflow `.github/workflows/checkov.yml` created: triggers on `push` and `pull_request` to `main`; runs `tofu fmt -check`, `tofu validate`, `tflint --recursive`, `checkov -d . --framework terraform --compact`; uploads Checkov JSON report as artifact
- [ ] All existing `#checkov:skip=CKV_AZURE_33` inline suppressions in `imaging/image-builder/main.tf` documented with justification comment
- [ ] `reports/` directory added to `.gitignore`
- [ ] `CHECKOV.md` created documenting: how to run locally, CI integration, suppression policy, list of currently suppressed checks with justifications
- [ ] All modules pass Checkov with 0 unsuppressed critical/high findings (or suppressions are justified)
- [ ] Passes all quality gates

---

### US-009: Add per-customer dedicated environment support with correct module composition

**Description:** As a platform engineer, I want the dedicated customer module to correctly compose networking, storage, AADDS integration, and AVD modules so that a new dedicated customer can be provisioned by adding a single call block in `environments/dedicated/`.

**Acceptance Criteria:**
- [ ] `modules/dedicated/main.tf` updated: `module.avd` call adds missing `domain_join_config` variable pass-through (currently not passed); adds `fslogix_config` pass-through to `module.avd`
- [ ] `modules/dedicated/main.tf`: `module.networking` uses `modules/networking` (correct); fix `azurerm_virtual_network_peering.reverse` bug (see US-002) so dedicated spoke peers correctly to hub
- [ ] `modules/dedicated/variables.tf` adds: `hub_vnet_id` (for peering), `aadds_dns_servers` (list of IPs), `hub_firewall_private_ip` (for UDR), `avd_image_id` (already exists)
- [ ] `modules/dedicated/main.tf` adds: `azurerm_route_table` + `azurerm_subnet_route_table_association` to route all spoke traffic through hub firewall (`0.0.0.0/0 -> var.hub_firewall_private_ip`)
- [ ] `modules/dedicated/main.tf` adds: VNet DNS servers set to `var.aadds_dns_servers` on the spoke VNet
- [ ] `environments/dedicated/customer-example.tf` updated to pass new required variables from networking layer outputs
- [ ] `environments/dedicated/` has its own `backend.hcl` with state key `environments/dedicated`
- [ ] `modules/dedicated/` passes all quality gates

---

### US-010: Implement RBAC and IAM for multi-tenant isolation

**Description:** As a security architect, I want fine-grained RBAC and IAM configured so that each customer in the shared environment can only access their own application group, file share, and data, with all assignments managed as code.

**Acceptance Criteria:**
- [ ] `modules/customer/main.tf` updated to create: `azurerm_role_assignment` for `Desktop Virtualization User` on the customer's RemoteApp application group; `azurerm_role_assignment` for `Storage File Data SMB Share Contributor` on the customer's FSLogix file share
- [ ] `modules/customer/variables.tf` adds: `application_group_id`, `fslogix_storage_account_id`, `customer_entra_group_object_id`
- [ ] Managed identity (System Assigned) on session hosts granted `Storage File Data SMB Share Contributor` on the shared FSLogix storage accounts
- [ ] Service principal for OpenTofu automation: documented in `BACKEND.md` with minimum required roles (`Contributor` on landing zone subscriptions, `User Access Administrator` scoped to resource groups only)
- [ ] All `azurerm_role_assignment` resources include `skip_service_principal_aad_check = false` where applicable
- [ ] Audit diagnostic settings: `azurerm_monitor_diagnostic_setting` added to Log Analytics for AVD host pools and application groups
- [ ] Passes all quality gates

---

### US-011: Fix known code defects and inconsistencies across modules

**Description:** As a platform engineer, I want all known bugs and inconsistencies in the existing module code resolved so that `tofu validate` and `tofu plan` complete without errors across all layers.

**Acceptance Criteria:**
- [ ] **`modules/networking/main.tf` line 127:** `virtual_network_name = var.peering_config.remote_vnet_id` — fix to reference the actual remote VNet name (add `remote_vnet_name` field to `peering_config` variable object)
- [ ] **`modules/fslogix/main.tf` lines 136-141:** `dynamic "virtual_network_subnet_ids"` is not a valid block in `azurerm_storage_account_network_rules` — replace with `virtual_network_subnet_ids = var.subnet_id != "" ? [var.subnet_id] : []` as a direct attribute
- [ ] **`modules/aadds/main.tf` line 66:** `azurerm_active_directory_domain_service_group_policy` — verify this resource exists in azurerm 4.x; if not, replace with `null_resource` + documented PowerShell approach
- [ ] **`modules/avd/main.tf` line 186:** `workspace_id = azurerm_virtual_desktop_workspace.this[each.value.host_pool_name].id` — workspace lookup key should be `each.value.name` (or the workspace name), not `host_pool_name`; fix association mapping
- [ ] **`bootstrap/main.tf` line 87:** `principal_id = azurerm_storage_account.this.identity.0.principal_id` — this assigns the storage account's managed identity to itself; this is likely incorrect; remove or replace with correct service principal assignment
- [ ] **`main.tf` lines 33-38:** root module calls `environments/shared` and `environments/dedicated` as modules, but those are root configurations (have their own backends); move to separate workspace invocations or restructure as proper child modules; add `WORKSPACES.md` entry explaining the layered deployment order
- [ ] All modules pass `tofu validate` with no errors after fixes
- [ ] Passes all quality gates

---

### US-012: Integrate Azure Verified Modules (AVM) for networking and storage

**Description:** As a platform engineer, I want to evaluate and integrate Azure Verified Modules for VNet, storage, and AVD components so that we leverage Microsoft-supported, well-tested patterns where they reduce custom code.

**Acceptance Criteria:**
- [ ] Research AVM registry (`azure/avm-res-network-virtualnetwork`, `azure/avm-res-storage-storageaccount`, `azure/avm-res-desktopvirtualization-hostpool`) for applicability
- [ ] For each evaluated AVM: document in `WORKSPACES.md` or dedicated `AVM.md` whether it was adopted or rejected, and why
- [ ] If AVM for VNet adopted: replace `modules/networking/main.tf` VNet + subnet resources with AVM call; wrap in thin module if customization needed
- [ ] If AVM for storage adopted: replace `modules/storage/main.tf` storage account resources with AVM call
- [ ] All AVM sources pinned to a specific version tag (no `latest`)
- [ ] `.terraform.lock.hcl` updated after AVM integration
- [ ] Passes all quality gates

---

### US-013: Improve documentation and add operational runbooks

**Description:** As an operations team, I want comprehensive, updated documentation reflecting all architectural decisions and correct deployment order so that the environment can be deployed, operated, and extended without expert assistance.

**Acceptance Criteria:**
- [ ] `README.md` updated: architecture overview, hub-and-spoke topology, module map, deployment order (bootstrap → networking → imaging → shared/dedicated)
- [ ] `WORKSPACES.md` updated: explains each OpenTofu workspace/root module, its state key, prerequisites, and deployment command
- [ ] `BACKEND.md` updated: OIDC setup instructions for GitHub Actions and Azure DevOps; required service principal roles
- [ ] `docs/runbook-add-customer.md` created: step-by-step for adding a new shared customer (add to `environments/shared/customer.tf`) and a new dedicated customer (add module call in `environments/dedicated/`)
- [ ] `docs/runbook-image-update.md` created: how to trigger a new golden image build and roll out to session hosts
- [ ] `docs/architecture-decisions.md` created: captures all decisions from Q&A sessions (shared RemoteApp only, Flexible VMSS, AADDS in hub, Checkov dual integration)
- [ ] All `.tf` files have module-level description comments at top
- [ ] Passes all quality gates (no `.md` files cause `tofu validate` failures)

---

## Functional Requirements

- **FR-1:** Bootstrap (`bootstrap/`) must provision state backend, management groups, hub VNet, Azure Firewall, Private DNS Zones, and Log Analytics in a single `tofu apply`
- **FR-2:** All session hosts must use `azurerm_orchestrated_virtual_machine_scale_set` (Flexible VMSS) with AVD DSC extension for host pool registration
- **FR-3:** Shared AVD environment must deliver LoB application as RemoteApp only — no Published Desktop
- **FR-4:** Per-customer Azure Premium File Shares must be provisioned for FSLogix profiles and one shared App Attach share must exist in the shared spoke
- **FR-5:** FSLogix profile container paths must be set via AADDS Group Policy (or equivalent registry push) — not hardcoded in session host images
- **FR-6:** AADDS must be deployed in the hub with DNS server IPs injected into all spoke VNet DNS settings
- **FR-7:** All spoke traffic to internet/storage must route through hub Azure Firewall via User Defined Routes
- **FR-8:** All Private Endpoints for storage must register A-records in hub Private DNS Zones
- **FR-9:** All OpenTofu code must pass `tofu fmt -check`, `tofu validate`, `tofu plan`, `tflint`, and `checkov` with 0 unsuppressed critical/high findings
- **FR-10:** Checkov must run via pre-commit hook (local) and CI pipeline (GitHub Actions)
- **FR-11:** The dedicated customer module must be invocable with a single `module` block accepting `customer_name`, `user_count`, `avd_image_id`, `hub_vnet_id`, `aadds_dns_servers`, `hub_firewall_private_ip`
- **FR-12:** All known code defects (reverse peering bug, invalid FSLogix network rules block, wrong workspace association key) must be resolved before any new feature work

## Non-Goals (Out of Scope)

- Published Desktop (full desktop) sessions in the shared environment
- Azure Virtual WAN — traditional VNet peering only
- Customer self-service portal or API for environment provisioning
- Multi-region / disaster recovery (DR host pools removed from scope for this iteration)
- On-premises connectivity (ExpressRoute/VPN gateway subnet reserved but not configured)
- Third-party identity providers (Entra/AADDS only)
- Custom Terraform provider development
- Performance testing and capacity planning
- Compliance certifications (FedRAMP, HIPAA, etc.)
- Azure DevOps pipeline YAML — GitHub Actions only for CI (Azure DevOps guidance in documentation only)

## Technical Considerations

- **AADDS deployment time:** 30–40 minutes; bootstrap must account for this with `depends_on` chains or a documented manual wait step
- **Flexible VMSS + AVD:** Host pool registration via DSC extension requires a valid registration token; token expiry management must be handled (use short-lived tokens, regenerated in pipeline)
- **Private DNS + Firewall:** DNS proxy on Azure Firewall must be enabled and spoke VNets must use firewall IP as DNS server for Private DNS resolution to work correctly
- **AVM version pinning:** Pin all AVM module versions in `.terraform.lock.hcl` to avoid unexpected upstream changes
- **Checkov suppressions:** Use inline `#checkov:skip=CHECK_ID:justification` in `.tf` files rather than blanket config skips to maintain auditability
- **FSLogix storage network rules bug:** The `dynamic "virtual_network_subnet_ids"` block must be fixed before any environment can successfully plan (FR-12)
- **Root module composition:** `main.tf` calling `environments/shared` and `environments/dedicated` as modules is architecturally incorrect for multi-backend setups; each environment must be applied separately per `WORKSPACES.md`
- **RemoteApp application group:** Requires explicit `azurerm_virtual_desktop_application` resources per published application; ensure LoB application executable path is parameterized

## Success Metrics

- `tofu validate` passes in all root modules and submodules with 0 errors
- `checkov -d . --framework terraform` reports 0 unsuppressed critical/high findings
- `tofu plan` completes in < 2 minutes for individual layers (networking, shared, dedicated)
- New dedicated customer can be onboarded by adding one `module` block and running `tofu apply`
- Golden image build completes without manual intervention via Image Builder template
- Session hosts successfully register with host pool using Flexible VMSS + DSC extension
- All private endpoints resolve via hub Private DNS Zones (verified by `nslookup` from session host)
- Checkov CI pipeline executes on every PR and blocks merge on critical findings

## Open Questions

- **DNS Proxy on Firewall:** Should Azure Firewall DNS proxy be enabled (required for Private DNS resolution from spokes)? This needs to be set in the Firewall Policy — confirm and add to US-001/US-002.
- **AADDS SKU:** Current code uses `var.sku` default — should this be `Standard` or `Enterprise`? Enterprise supports more objects and replica sets.
- **App Attach mechanism:** MSIX App Attach (classic) vs new App Attach (portal-managed, GA 2024) — decision deferred; which should be the default variable value?
- **Image update frequency:** How often will the golden image be rebuilt? This impacts whether the Image Builder template trigger should be time-based or change-based.
- **Token rotation:** AVD host pool registration tokens expire; what is the token management strategy for Flexible VMSS (tokens cannot be rotated in-place without re-registering)?