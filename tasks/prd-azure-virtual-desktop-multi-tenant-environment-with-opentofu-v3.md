# PRD: Azure Virtual Desktop Multi-Tenant Environment with OpenTofu (v3)

## Overview

Extend and complete the production-grade Azure Virtual Desktop (AVD) environment. V3 targets four goals:
1. Fill all implementation gaps remaining after v2 (App Attach dedicated storage, monitoring wired into environments, AVM gap analysis extended).
2. Resolve all open questions from v2 and record decisions as Architecture Decision Records.
3. Add OpenTofu unit tests (`.tftest.hcl` with mock providers) for each module.
4. Ensure the full codebase is clean: `tofu validate`, `tofu fmt`, Checkov, and tflint all pass.

The environment follows Azure Landing Zone / CAF, Well-Architected Framework, Hub-and-Spoke with Azure Firewall, AADDS, Flexible VMSS, FSLogix, Checkov CI, and platform-team-managed provisioning. No new architectural decisions are introduced without an ADR.

**Key decisions resolved in v3 (carried forward from v2 open questions):**

| Decision | Resolution |
|---|---|
| DNS Proxy on Firewall | Enabled — `dns { proxy_enabled = true }` in `azurerm_firewall_policy` |
| AADDS SKU | `Standard` — upgrade path to Enterprise documented in ADR |
| App Attach mechanism | New App Attach (GA 2024, portal-managed) as default; `app_attach_type = "AppAttach"` variable-selectable |
| Image update trigger | Change-based — pipeline triggers on Git tag push to `imaging/` path |
| Token rotation | 2-hour expiry; `azurerm_virtual_desktop_host_pool_registration_info` regenerated on each pipeline run |
| AVM — five additional modules | Key Vault, Log Analytics, Azure Firewall Policy, Managed Identity, Image Builder — evaluated in `AVM.md` |

**Carried forward from v2 (all remain in scope):**
- Shared pool: RemoteApp-only, no Published Desktop
- AADDS: single shared instance in hub; DNS proxy enabled
- Bootstrap: provisions state backend + Hub VNet + Azure Firewall
- Checkov: local pre-commit hook + GitHub Actions CI
- Platform team only manages all environments

---

## Quality Gates

Every user story must pass all of the following before being marked complete:

```
tofu fmt -check                                       # format check
tofu validate                                         # schema + reference validation
tofu plan -var-file=terraform.tfvars                  # dry-run (mock .tfvars acceptable for modules)
checkov -d . --framework opentofu --compact           # 0 unsuppressed critical/high
tflint --recursive                                    # 0 errors
```

Additional gates for stories touching networking, storage, or identity:
- `CKV_AZURE_*` critical findings = 0 unsuppressed in all changed modules
- `tofu validate` must succeed in both `bootstrap/` and root module context

Additional gates for test stories (US-018, US-019, US-020):
- `tofu test` must exit 0 in the target module directory
- Mock provider must not require real Azure credentials

---

## User Stories

---

### US-014: Resolve open architectural questions and record Architecture Decision Records

**Description:** As a platform architect, I want all open questions from the v2 PRD resolved and recorded in `docs/architecture-decisions.md` so the team has a single authoritative source before starting new implementation work.

**Acceptance Criteria:**
- [ ] `docs/architecture-decisions.md` created (or updated if it exists) with five new ADR entries using the format: **Decision, Rationale, Consequences, Alternatives Considered**:
  1. DNS Proxy on Azure Firewall — enabled; reason: required for Private DNS resolution from spokes
  2. AADDS SKU — Standard; reason: sufficient for expected user count; Enterprise upgrade path documented
  3. App Attach mechanism — new App Attach (GA 2024) as default; MSIX App Attach selectable via `app_attach_type = "MsixAppAttach"`
  4. Image update trigger — change-based Git tag push to `imaging/` path; reason: avoids unnecessary image rebuilds on unrelated commits
  5. Token rotation strategy — 2-hour expiry; `azurerm_virtual_desktop_host_pool_registration_info` regenerated on each pipeline run; token passed to DSC extension as sensitive variable
- [ ] `WORKSPACES.md` updated: deployment order table includes `imaging/image-builder` as step 3 (after `networking/hub-and-spoke/`, before `environments/`)
- [ ] `WORKSPACES.md` includes a note that `networking/hub-and-spoke/` must be re-applied after AADDS deployment to inject AADDS DNS IPs (two-pass deployment)
- [ ] `README.md` updated: "Open Questions" section replaced with reference to `docs/architecture-decisions.md`
- [ ] Quality gates pass (no `.tf` changes in this story — `tofu fmt -check` on existing files only)

---

### US-015: Enable Azure Firewall DNS proxy and wire AADDS DNS into spoke VNets

**Description:** As a network engineer, I want Azure Firewall DNS proxy enabled and AADDS DNS server IPs injected into all spoke VNet DNS settings so that Private DNS resolution and AADDS domain join work correctly from session hosts without any manual DNS configuration.

**Acceptance Criteria:**
- [ ] `networking/hub-and-spoke/main.tf`: `azurerm_firewall_policy` resource gains a `dns` block: `proxy_enabled = true`; `servers = var.aadds_dns_server_ips` (conditional — only set when list is non-empty)
- [ ] `networking/hub-and-spoke/variables.tf`: adds variable `aadds_dns_server_ips` — `list(string)`, default `[]`, description: "AADDS-assigned DNS server IPs — populate after AADDS deployment (two-pass)"
- [ ] `networking/hub-and-spoke/main.tf`: `azurerm_virtual_network` resources for shared spoke and dedicated spoke gain `dns_servers = length(var.aadds_dns_server_ips) > 0 ? var.aadds_dns_server_ips : null`
- [ ] `networking/hub-and-spoke/outputs.tf`: exports `firewall_dns_proxy_enabled` (bool) and `hub_firewall_private_ip` (string — firewall private IP, if not already exported)
- [ ] `docs/architecture-decisions.md` DNS Proxy ADR includes note: first apply with `aadds_dns_server_ips = []`; re-apply after AADDS provisions with actual IPs
- [ ] All quality gates pass in `networking/hub-and-spoke/`

---

### US-016: Implement dedicated App Attach Premium File Share and AVD App Attach configuration

**Description:** As a platform engineer, I want a dedicated Azure Premium File Share for App Attach packages (separate from FSLogix shares) and AVD App Attach variables wired through to the module interfaces, so that applications can be delivered via App Attach without modifying the base image.

**Acceptance Criteria:**
- [ ] `modules/storage/main.tf`: when a `storage_account_config` entry has `purpose = "appattach"` (new optional field, default `"fslogix"`), creates a Premium FileStorage account + file share named `appattach` with `quota_gib` (default 100)
- [ ] `modules/storage/variables.tf`: `storage_account_config` object type updated to include optional `purpose` field (string, default `"fslogix"`)
- [ ] `environments/shared/locals.tf`: adds one `appattach` storage account entry in `premium_storage_accounts` with `purpose = "appattach"` and a `appattach` file share in `premium_file_shares`; private endpoint registered in `snet-shared-storage`
- [ ] `modules/avd/variables.tf`: adds two new variables:
  - `app_attach_type` — string, default `"AppAttach"`, validation: `one_of(["AppAttach", "MsixAppAttach", "None"])`
  - `app_attach_packages` — `list(object({ name, path, msix_package_family_name, msix_image_path }))`, default `[]`
- [ ] `modules/avd/main.tf`: when `var.app_attach_type != "None"`, `azurerm_virtual_desktop_host_pool` resources gain `start_vm_on_connect = true`
- [ ] `modules/dedicated/variables.tf`: forwards `app_attach_type` (default `"AppAttach"`) and `app_attach_packages` (default `[]`) to `module.avd`
- [ ] RBAC: `Storage File Data SMB Share Contributor` role assigned to each session host VMSS user-assigned managed identity on the `appattach` storage account
- [ ] Private DNS A-record for `appattach` storage account registered in hub `privatelink.file.core.windows.net` Private DNS Zone
- [ ] `tofu validate` passes in `environments/shared/` and `modules/dedicated/`
- [ ] All quality gates pass

---

### US-017: Wire monitoring module into shared and dedicated environments with AVD-specific diagnostics

**Description:** As an operations engineer, I want the existing `modules/monitoring` module connected to both shared and dedicated environments with AVD-specific metric alerts and Log Analytics workspace ID passed into `modules/avd`, so that session host health, user connection failures, and VMSS CPU/memory are observable from day one.

**Acceptance Criteria:**
- [ ] `environments/shared/main.tf`: `module.avd` gains `log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id` (pass through the workspace ID output from `module.monitoring`)
- [ ] `modules/monitoring/outputs.tf`: exports `log_analytics_workspace_id` (string — the workspace resource ID, empty string if workspace not created)
- [ ] `environments/shared/locals.tf`: `metric_alerts` local includes at minimum three AVD-relevant alerts:
  1. Session host CPU > 85% for 5 minutes (severity 2) — `Microsoft.Compute/virtualMachineScaleSets` namespace, metric `Percentage CPU`
  2. Session host available memory < 512 MB (severity 2) — metric `Available Memory Bytes`
  3. Host pool user connection failures > 5 in 5 minutes (severity 1) — `Microsoft.DesktopVirtualization/hostpools` namespace, metric `UserConnectionCount` (if available) or use `azurerm_monitor_scheduled_query_rules_alert` on the Log Analytics workspace
- [ ] `environments/shared/locals.tf`: `diagnostic_settings` local populated with at least one entry for the shared host pool (target_resource_id = AVD host pool resource ID, using `module.avd` outputs)
- [ ] `modules/dedicated/variables.tf`: adds `log_analytics_workspace_id` (string, default `""`)
- [ ] `modules/dedicated/main.tf`: passes `log_analytics_workspace_id` to `module.avd`
- [ ] `environments/dedicated/main.tf` (or `customer-example.tf`): example dedicated customer call includes `log_analytics_workspace_id` wired from a shared monitoring workspace output or a local workspace
- [ ] `tofu validate` passes in `environments/shared/` and `modules/dedicated/`
- [ ] All quality gates pass

---

### US-018: OpenTofu unit tests for `modules/networking`

**Description:** As a platform engineer, I want `.tftest.hcl` unit tests for `modules/networking` using mock providers so that the module's resource structure, variable defaults, and NSG rule generation are verified without requiring Azure credentials or a live environment.

**Acceptance Criteria:**
- [ ] `modules/networking/tests/unit.tftest.hcl` created
- [ ] Test file uses `mock_provider "azurerm" {}` block (OpenTofu 1.7+ mock syntax)
- [ ] At minimum three `run` blocks:
  1. **`test_default_vnet_config`** — calls module with minimal required variables; asserts `output.vnet_id` is not empty string; asserts `output.subnet_ids` map contains expected subnet keys
  2. **`test_nsg_rules_applied`** — calls module with a custom `nsg_rules` list; asserts plan does not error; asserts NSG resource count > 0
  3. **`test_firewall_disabled`** — calls module with `enable_firewall = false`; asserts no `azurerm_firewall` resource is planned
- [ ] `tofu test` exits 0 in `modules/networking/`
- [ ] A mock `.tfvars` file `modules/networking/tests/mock.tfvars` is provided with all required variables populated with synthetic values
- [ ] All quality gates pass

---

### US-019: OpenTofu unit tests for `modules/avd`

**Description:** As a platform engineer, I want `.tftest.hcl` unit tests for `modules/avd` using mock providers so that host pool creation, application group association, VMSS session host configuration, and scaling plan wiring are validated without Azure credentials.

**Acceptance Criteria:**
- [ ] `modules/avd/tests/unit.tftest.hcl` created
- [ ] Uses `mock_provider "azurerm" {}` and `mock_provider "random" {}`
- [ ] At minimum four `run` blocks:
  1. **`test_host_pool_created`** — minimal config; asserts `output.host_pool_ids` map is non-empty
  2. **`test_app_group_workspace_association`** — provides one host pool + one workspace + one app group; asserts no plan errors (validates the workspace association key fix from US-011)
  3. **`test_vmss_session_hosts`** — provides one `session_host_config` entry; asserts `azurerm_orchestrated_virtual_machine_scale_set` count = 1 in plan
  4. **`test_scaling_plan_optional`** — first run with `scaling_plan_config = null`; asserts no scaling plan resource; second run with `scaling_plan_config` populated; asserts scaling plan count = 1
- [ ] `tofu test` exits 0 in `modules/avd/`
- [ ] Mock `.tfvars` file `modules/avd/tests/mock.tfvars` provided
- [ ] All quality gates pass

---

### US-020: OpenTofu unit tests for `modules/storage` and `modules/dedicated`

**Description:** As a platform engineer, I want `.tftest.hcl` unit tests for `modules/storage` and `modules/dedicated` using mock providers so that storage account creation, file share provisioning, private endpoint configuration, and the complete dedicated customer module composition are verified without Azure credentials.

**Acceptance Criteria:**
- [ ] `modules/storage/tests/unit.tftest.hcl` created with at minimum three `run` blocks:
  1. **`test_storage_accounts_created`** — provides two entries in `storage_account_config`; asserts two storage account resources in plan
  2. **`test_file_shares_created`** — provides one storage account + two file shares; asserts two file share resources
  3. **`test_private_endpoints_optional`** — verifies private endpoint resources = 0 when `private_endpoint_config = []`; = 1 when one entry provided
- [ ] `modules/dedicated/tests/unit.tftest.hcl` created with at minimum two `run` blocks:
  1. **`test_default_dedicated_module`** — provides only `customer_name`, `location`, `vnet_config`, `resource_group_name`; asserts no plan errors; asserts `output.host_pool_ids` is non-empty
  2. **`test_hub_peering`** — provides `hub_vnet_id` and `hub_vnet_name`; asserts `azurerm_virtual_network_peering` count ≥ 1
- [ ] `tofu test` exits 0 in both `modules/storage/` and `modules/dedicated/`
- [ ] Mock `.tfvars` files provided for both modules
- [ ] All quality gates pass

---

### US-021: Evaluate five additional AVM modules and update AVM.md

**Description:** As a platform engineer, I want five additional Azure Verified Modules evaluated against this codebase (Key Vault, Log Analytics Workspace, Azure Firewall Policy, User-Assigned Managed Identity, Azure Image Builder) and the decisions recorded in `AVM.md`, so that we maintain a complete, up-to-date record of AVM adoption decisions.

**Acceptance Criteria:**
- [ ] `AVM.md` updated with five new evaluation sections following the same format as the existing three (Module name + version, What it does, Why adopted/rejected, Decision)
- [ ] Modules to evaluate (use latest available version at time of evaluation):
  1. `azure/avm-res-keyvault-vault` — evaluate for replacing any inline Key Vault resources
  2. `azure/avm-res-operationalinsights-workspace` — evaluate for replacing `azurerm_log_analytics_workspace` in `modules/monitoring`
  3. `azure/avm-res-network-firewallpolicy` — evaluate for the `azurerm_firewall_policy` resource in `networking/hub-and-spoke`
  4. `azure/avm-res-managedidentity-userassignedidentity` — evaluate for replacing `azurerm_user_assigned_identity` in `modules/avd`
  5. `azure/avm-res-resources-resourcegroup` — evaluate for resource group creation pattern across all modules
- [ ] For each module: record registry URL, GitHub URL, version evaluated, interface comparison with current code, provider requirements, stability status, and final decision
- [ ] Summary table at top of `AVM.md` updated with all eight entries (three existing + five new)
- [ ] "Recommendation for Future Review" section updated with any new conditions
- [ ] No `.tf` changes required — this is a documentation story
- [ ] Quality gates: `tofu fmt -check` on existing files

---

### US-022: Harden registration token expiry and pipeline token rotation

**Description:** As a security engineer, I want the AVD host pool registration token expiry reduced from the current hardcoded `2027-12-31` date to a 2-hour rolling window regenerated on each pipeline run, so that leaked tokens cannot be used to register unauthorized session hosts.

**Acceptance Criteria:**
- [ ] `modules/avd/main.tf`: `azurerm_virtual_desktop_host_pool_registration_info.this` — remove hardcoded `expiration_date = "2027-12-31T00:00:00Z"`; replace with `expiration_date = timeadd(timestamp(), "2h")`
- [ ] `modules/avd/main.tf`: registration info resource gains `lifecycle { replace_triggered_by = [azurerm_virtual_desktop_host_pool.this] }` to ensure token is regenerated when host pool changes
- [ ] `modules/avd/main.tf`: the `RegistrationInfoToken` in the DSC extension `settings` block already references `azurerm_virtual_desktop_host_pool_registration_info.this[each.value.host_pool_name].token` — verify this reference is correct and the token is passed as a protected_setting (not plain settings) to avoid token exposure in state diff output
- [ ] `docs/architecture-decisions.md` ADR for token rotation updated with: `timeadd(timestamp(), "2h")` pattern; note that this causes the resource to be replaced on every `tofu apply` which is expected behavior for token rotation
- [ ] `.github/workflows/` (or equivalent CI file) gains a note/comment: "tofu apply regenerates registration token on each run by design"
- [ ] `tofu validate` passes in `modules/avd/`
- [ ] All quality gates pass

---

### US-023: Validate and clean up entire codebase — full quality gate sweep

**Description:** As a platform engineer, I want to run all quality gates across every module and environment in the repository and fix any remaining errors, warnings, or suppressions that are not properly justified, so that the codebase is in a clean, deployable state at the end of v3.

**Acceptance Criteria:**
- [ ] `tofu fmt -recursive` applied to all `.tf` files; resulting diff is zero (all files already formatted)
- [ ] `tofu validate` exits 0 in: `bootstrap/`, `networking/hub-and-spoke/`, `modules/networking/`, `modules/avd/`, `modules/storage/`, `modules/monitoring/`, `modules/fslogix/`, `modules/aadds/`, `modules/dedicated/`, `modules/customer/`, `imaging/image-builder/`, `environments/shared/`, `environments/dedicated/`
- [ ] `tflint --recursive` exits 0 (0 errors; warnings documented in `CHECKOV.md` or inline)
- [ ] `checkov -d . --framework opentofu --compact` reports 0 unsuppressed critical/high findings; all suppressions have `#checkov:skip=CHECK_ID:justification` inline comments
- [ ] Any remaining known defects from US-011 that were not already resolved are fixed in this story (the US-011 checklist is used as the defect backlog reference)
- [ ] `modules/monitoring/main.tf`: remove standalone `provider "azurerm"` block (child modules must not declare providers; only root modules declare providers) — verify this is consistent across all child modules
- [ ] All quality gates pass

---

## Functional Requirements

*(Carried forward from v2 + v3 additions in bold)*

- **FR-1:** Bootstrap must provision state backend, management groups, hub VNet, Azure Firewall, Private DNS Zones, and Log Analytics in a single `tofu apply`
- **FR-2:** All session hosts must use `azurerm_orchestrated_virtual_machine_scale_set` (Flexible VMSS) with AVD DSC extension
- **FR-3:** Shared AVD environment must deliver LoB application as RemoteApp only — no Published Desktop
- **FR-4:** Per-customer Azure Premium File Shares must be provisioned for FSLogix profiles; one dedicated App Attach Premium File Share must exist in the shared spoke
- **FR-5:** FSLogix profile container paths must be set via AADDS Group Policy
- **FR-6:** AADDS DNS server IPs must be injected into all spoke VNet DNS settings; Azure Firewall DNS proxy must be enabled
- **FR-7:** All spoke traffic must route through hub Azure Firewall via UDR
- **FR-8:** All Private Endpoints for storage must register A-records in hub Private DNS Zones
- **FR-9:** All OpenTofu code must pass `tofu fmt -check`, `tofu validate`, `tofu plan`, `tflint`, and Checkov with 0 unsuppressed critical/high findings
- **FR-10:** Checkov must run via pre-commit hook (local) and GitHub Actions CI
- **FR-11:** Dedicated customer module invocable with a single `module` block
- **FR-12:** All known code defects from US-011 must be resolved
- **FR-13 (new):** AVD host pool registration token expiry must be ≤ 2 hours; tokens must be regenerated on each pipeline run
- **FR-14 (new):** Each module must have at least one `.tftest.hcl` unit test passing with mock providers
- **FR-15 (new):** A dedicated App Attach Premium File Share must exist separate from FSLogix shares
- **FR-16 (new):** `modules/monitoring` must be wired into both shared and dedicated environments with AVD-specific metric alerts

---

## Non-Goals (Out of Scope for v3)

*(Carried forward from v2)*
- Published Desktop (full desktop) in the shared environment
- Azure Virtual WAN
- Customer self-service portal or API
- Multi-region / disaster recovery
- On-premises connectivity (ExpressRoute/VPN)
- Third-party identity providers
- Custom provider development
- Performance testing / capacity planning
- Compliance certifications
- Azure DevOps pipeline YAML (GitHub Actions only)

---

## Technical Considerations

- **`timeadd(timestamp(), "2h")` for token expiry:** This causes `azurerm_virtual_desktop_host_pool_registration_info` to show as "replace" on every `tofu plan`. This is expected and by design — document in ADR and in pipeline comments.
- **Provider block in child modules:** `provider "azurerm" { features {} }` must NOT appear in child modules (only root modules). US-023 enforces this. Current `modules/monitoring/main.tf` has a standalone provider block that must be removed.
- **Mock provider syntax:** OpenTofu 1.7+ supports `mock_provider` in `.tftest.hcl`. All test stories assume OpenTofu ≥ 1.7.
- **App Attach `azurerm_virtual_desktop_application` vs ARM:** The `azurerm_virtual_desktop_application` resource does not natively support App Attach package registration (that is done via the Azure Portal or REST API). The IaC story for US-016 handles the storage and RBAC layers; App Attach package registration itself is documented as a post-deployment manual step in `docs/runbook-add-customer.md`.
- **AVM evaluation scope (US-021):** Evaluation is documentation-only — no AVM modules are adopted unless evaluation results in an explicit adoption decision. Based on v2 findings, rejection is the expected outcome for most modules until they reach v1.0.
- **Checkov + `timeadd`:** Checkov may flag `timeadd(timestamp(), ...)` as non-deterministic. Suppress with `#checkov:skip=CKV2_AZURE_*:token-rotation-by-design` if needed.

---

## Success Metrics

- `tofu validate` passes in all 13 root modules / submodule directories with 0 errors
- `checkov` reports 0 unsuppressed critical/high findings across the entire repo
- `tofu test` exits 0 in `modules/networking/`, `modules/avd/`, `modules/storage/`, `modules/dedicated/`
- AVD host pool registration token expiry is ≤ 2 hours
- App Attach Premium File Share exists and is correctly configured in `environments/shared/`
- Monitoring module is wired into both shared and dedicated environments
- Five additional AVM modules evaluated and decisions recorded in `AVM.md`
- All v2 open questions resolved with ADRs in `docs/architecture-decisions.md`

---

## Dependency Order

Stories can be worked in parallel within a tier. Complete lower tiers before starting higher tiers.

| Tier | Stories | Notes |
|---|---|---|
| 1 — Foundation | US-014, US-022, US-023 | Documentation + token fix + code cleanup; no cross-story deps |
| 2 — Implementation | US-015, US-016, US-017 | Networking, App Attach, Monitoring wiring; US-015 before US-016 (DNS needed) |
| 3 — Tests | US-018, US-019, US-020 | Unit tests; depend on modules being clean (Tier 1 + 2 complete) |
| 4 — AVM Research | US-021 | Documentation only; can run in parallel with Tier 2/3 |
