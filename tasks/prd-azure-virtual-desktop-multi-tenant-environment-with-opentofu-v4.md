# PRD: Azure Virtual Desktop Multi-Tenant Environment with OpenTofu (v4)

## Overview

Complete the remaining implementation gaps in the production-grade Azure Virtual Desktop (AVD) platform. V4 targets the stories from the v3 PRD that were not yet implemented: DNS proxy wiring, App Attach AVD module variables, monitoring wired into AVD, OpenTofu unit tests for all modules, and registration token hardening. The codebase already has a complete hub-and-spoke topology, shared and dedicated AVD environments, FSLogix storage, AADDS integration, Image Builder pipeline, Checkov CI, and full documentation (v1–v3 complete).

**Scope:** Close the delta between the v3 PRD and current codebase state. No new architectural decisions are required; all relevant ADRs already exist in `docs/architecture-decisions.md`.

**Reference architecture:** `AVD_Reference_Architecture.pdf` and `Reference_Architecture.jpg` in repo root.

---

## Quality Gates

These commands must pass for every user story:

```
tofu fmt -check -recursive                            # format check (all .tf files)
tofu validate                                         # schema + reference validation
checkov -d . --config-file checkov-config.yaml --compact   # 0 unsuppressed critical/high
tflint --recursive                                    # 0 errors
```

For test stories (US-018, US-019, US-020), also run:

```
tofu test                                             # must exit 0 in target module directory
```

Note: `checkov` requires `--framework terraform` (not `opentofu`) as per ADR-005. The `checkov-config.yaml` already sets this.

---

## User Stories

---

### US-015: Enable Azure Firewall DNS proxy and finalise AADDS DNS wiring

**Description:** As a network engineer, I want Azure Firewall DNS proxy enabled in the Firewall Policy and the AADDS DNS wiring verified end-to-end, so that Private DNS resolution and AADDS domain join work correctly from all session hosts.

**Acceptance Criteria:**
- [ ] `networking/hub-and-spoke/main.tf`: `azurerm_firewall_policy` resource gains a `dns { proxy_enabled = true; servers = length(var.aadds_dns_server_ips) > 0 ? var.aadds_dns_server_ips : [] }` block
- [ ] `networking/hub-and-spoke/outputs.tf`: exports `firewall_dns_proxy_enabled` (bool, value = `true`) and `hub_firewall_private_ip` (string — firewall private IP) if not already exported
- [ ] `networking/hub-and-spoke/variables.tf`: `aadds_dns_server_ips` variable already exists — verify description says "populate after AADDS deployment (two-pass)"
- [ ] `docs/architecture-decisions.md`: DNS Proxy ADR updated (or added if missing) with note: first apply with `aadds_dns_server_ips = []`; re-apply after AADDS provisions with actual IPs
- [ ] All quality gates pass in `networking/hub-and-spoke/`

---

### US-016: Complete App Attach AVD module variables and RBAC

**Description:** As a platform engineer, I want the AVD module to expose App Attach type and package variables, and the session host managed identity to have `Storage File Data SMB Share Contributor` on the App Attach storage account, so that applications can be delivered via App Attach without modifying the base image.

**Acceptance Criteria:**
- [ ] `modules/avd/variables.tf`: adds `app_attach_type` — `string`, default `"AppAttach"`, validation `one_of(["AppAttach", "MsixAppAttach", "None"])`
- [ ] `modules/avd/variables.tf`: adds `app_attach_packages` — `list(object({ name = string, path = string }))`, default `[]`
- [ ] `modules/avd/main.tf`: when `var.app_attach_type != "None"`, `azurerm_virtual_desktop_host_pool` resources gain `start_vm_on_connect = true`
- [ ] `modules/dedicated/variables.tf`: forwards `app_attach_type` (default `"AppAttach"`) and `app_attach_packages` (default `[]`) to `module.avd`
- [ ] `environments/shared/main.tf`: the existing `appattach` storage account (already in `locals.tf`) has `Storage File Data SMB Share Contributor` RBAC assigned to each session host VMSS user-assigned managed identity
- [ ] `environments/shared/locals.tf` or `main.tf`: `module.avd` call includes `app_attach_type = "AppAttach"`
- [ ] `tofu validate` passes in `environments/shared/` and `modules/dedicated/`
- [ ] All quality gates pass

---

### US-017: Wire monitoring module into shared and dedicated environments with AVD-specific alerts

**Description:** As an operations engineer, I want the existing `modules/monitoring` module connected to `modules/avd` in both shared and dedicated environments with AVD-specific metric alerts, so that session host health, user connection failures, and VMSS CPU/memory are observable from day one.

**Acceptance Criteria:**
- [ ] `environments/shared/main.tf`: `module.avd` call gains `log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id`
- [ ] `modules/avd/variables.tf`: adds `log_analytics_workspace_id` — `string`, default `""`, description "Log Analytics workspace resource ID for AVD diagnostic settings"
- [ ] `modules/avd/main.tf`: when `var.log_analytics_workspace_id != ""`, `azurerm_monitor_diagnostic_setting` is created for each `azurerm_virtual_desktop_host_pool` resource, forwarding `Connection` and `Error` logs to the workspace
- [ ] `environments/shared/locals.tf`: `metric_alerts` local includes at minimum three AVD-relevant alerts:
  1. Session host CPU > 85% for 5 minutes (severity 2) — `Microsoft.Compute/virtualMachineScaleSets`, metric `Percentage CPU`
  2. Session host available memory < 512 MB (severity 2) — metric `Available Memory Bytes`
  3. Host pool user connection failures — `Microsoft.DesktopVirtualization/hostpools` namespace (use `azurerm_monitor_scheduled_query_rules_alert` on the Log Analytics workspace if metric is not available)
- [ ] `modules/dedicated/variables.tf`: adds `log_analytics_workspace_id` (string, default `""`)
- [ ] `modules/dedicated/main.tf`: passes `log_analytics_workspace_id` to `module.avd`
- [ ] `environments/dedicated/customer-example.tf` (or equivalent): example dedicated customer call includes `log_analytics_workspace_id` — can be empty string or wired from a local variable
- [ ] `tofu validate` passes in `environments/shared/` and `modules/dedicated/`
- [ ] All quality gates pass

---

### US-022: Harden registration token expiry to 2-hour rolling window

**Description:** As a security engineer, I want the AVD host pool registration token expiry changed from the hardcoded `2027-12-31` date to a 2-hour rolling window regenerated on each pipeline run, so that a leaked token cannot be used to register unauthorized session hosts.

**Acceptance Criteria:**
- [ ] `modules/avd/main.tf`: `azurerm_virtual_desktop_host_pool_registration_info.this` — replace `expiration_date = "2027-12-31T00:00:00Z"` with `expiration_date = timeadd(timestamp(), "2h")`
- [ ] `modules/avd/main.tf`: registration info resource gains `lifecycle { replace_triggered_by = [azurerm_virtual_desktop_host_pool.this] }` to ensure token is regenerated when the host pool changes
- [ ] `modules/avd/main.tf`: verify the `RegistrationInfoToken` in the DSC extension `settings` block is passed as a `protected_settings` entry (not plain `settings`) to avoid token exposure in plan output — if currently in `settings`, move to `protected_settings`
- [ ] `docs/architecture-decisions.md`: token rotation ADR entry added (or updated) with: `timeadd(timestamp(), "2h")` pattern; note that this causes the resource to show as "replace" on every `tofu plan` — this is expected and by design
- [ ] `.github/workflows/` pipeline YAML gains a comment: "tofu apply regenerates registration token on each run by design"
- [ ] `tofu validate` passes in `modules/avd/`
- [ ] All quality gates pass

---

### US-018: OpenTofu unit tests for `modules/networking`

**Description:** As a platform engineer, I want `.tftest.hcl` unit tests for `modules/networking` using mock providers so that the module's resource structure, variable defaults, and NSG rule generation are verified without requiring Azure credentials or a live environment.

**Acceptance Criteria:**
- [ ] `modules/networking/tests/unit.tftest.hcl` created
- [ ] Test file uses `mock_provider "azurerm" {}` block (OpenTofu 1.7+ mock syntax)
- [ ] At minimum three `run` blocks:
  1. **`test_default_vnet_config`** — calls module with minimal required variables; asserts `output.vnet_id` is not empty string; asserts `output.subnet_ids` map contains expected subnet keys
  2. **`test_nsg_rules_applied`** — calls module with a custom `nsg_rules` list; asserts plan succeeds; asserts NSG resource count > 0
  3. **`test_firewall_disabled`** — calls module with `enable_firewall = false`; asserts no `azurerm_firewall` resource is planned
- [ ] `modules/networking/tests/mock.tfvars` created with all required variables populated with synthetic values (no real Azure resource IDs or secrets)
- [ ] `tofu test` exits 0 in `modules/networking/`
- [ ] All quality gates pass

---

### US-019: OpenTofu unit tests for `modules/avd`

**Description:** As a platform engineer, I want `.tftest.hcl` unit tests for `modules/avd` using mock providers so that host pool creation, application group association, VMSS session host configuration, and scaling plan wiring are validated without Azure credentials.

**Acceptance Criteria:**
- [ ] `modules/avd/tests/unit.tftest.hcl` created
- [ ] Uses `mock_provider "azurerm" {}` and `mock_provider "random" {}`
- [ ] At minimum four `run` blocks:
  1. **`test_host_pool_created`** — minimal config; asserts `output.host_pool_ids` map is non-empty
  2. **`test_app_group_workspace_association`** — provides one host pool + one workspace + one app group; asserts no plan errors
  3. **`test_vmss_session_hosts`** — provides one `session_host_config` entry; asserts `azurerm_orchestrated_virtual_machine_scale_set` count = 1 in plan
  4. **`test_scaling_plan_optional`** — first run with `scaling_plan_config = null`; asserts no scaling plan resource; second run with `scaling_plan_config` populated; asserts scaling plan count = 1
- [ ] `modules/avd/tests/mock.tfvars` created with all required variables populated with synthetic values
- [ ] `tofu test` exits 0 in `modules/avd/`
- [ ] All quality gates pass

---

### US-020: OpenTofu unit tests for `modules/storage` and `modules/dedicated`

**Description:** As a platform engineer, I want `.tftest.hcl` unit tests for `modules/storage` and `modules/dedicated` using mock providers so that storage account creation, file share provisioning, private endpoint configuration, and the complete dedicated customer module composition are verified without Azure credentials.

**Acceptance Criteria:**
- [ ] `modules/storage/tests/unit.tftest.hcl` created with at minimum three `run` blocks:
  1. **`test_storage_accounts_created`** — provides two entries in `storage_account_config`; asserts two `azurerm_storage_account` resources in plan
  2. **`test_file_shares_created`** — provides one storage account + two file shares in config; asserts two `azurerm_storage_share` resources
  3. **`test_private_endpoints_optional`** — verifies `azurerm_private_endpoint` count = 0 when `private_endpoint_config = []`; count = 1 when one entry provided
- [ ] `modules/dedicated/tests/unit.tftest.hcl` created with at minimum two `run` blocks:
  1. **`test_default_dedicated_module`** — provides only `customer_name`, `location`, `vnet_config`, `resource_group_name`; asserts no plan errors; asserts `output.host_pool_ids` is non-empty
  2. **`test_hub_peering`** — provides `hub_vnet_id` and `hub_vnet_name`; asserts `azurerm_virtual_network_peering` count ≥ 1
- [ ] Mock `.tfvars` files provided for both modules (`modules/storage/tests/mock.tfvars`, `modules/dedicated/tests/mock.tfvars`)
- [ ] `tofu test` exits 0 in both `modules/storage/` and `modules/dedicated/`
- [ ] All quality gates pass

---

### US-021: Evaluate five additional AVM modules and update AVM.md

**Description:** As a platform engineer, I want five additional Azure Verified Modules evaluated against this codebase and the decisions recorded in `AVM.md`, so that we maintain a complete, up-to-date record of AVM adoption decisions.

**Acceptance Criteria:**
- [ ] `AVM.md` updated with five new evaluation sections using the same format as the three existing entries (Module name + registry URL + GitHub URL + version, "What it does", "Why adopted/rejected", "Decision")
- [ ] Modules to evaluate (use latest available version at time of evaluation):
  1. `azure/avm-res-keyvault-vault` — evaluate for any Key Vault resources in the codebase
  2. `azure/avm-res-operationalinsights-workspace` — evaluate for `azurerm_log_analytics_workspace` in `modules/monitoring`
  3. `azure/avm-res-network-firewallpolicy` — evaluate for `azurerm_firewall_policy` in `networking/hub-and-spoke`
  4. `azure/avm-res-managedidentity-userassignedidentity` — evaluate for `azurerm_user_assigned_identity` in `modules/avd`
  5. `azure/avm-res-resources-resourcegroup` — evaluate for the resource group creation pattern across all modules
- [ ] Summary table at top of `AVM.md` updated with all eight entries (three existing + five new)
- [ ] "Recommendation for Future Review" section updated with any new conditions identified during evaluation
- [ ] No `.tf` files are changed unless an evaluation results in an explicit adoption decision (rejection is the expected outcome based on v2 findings)
- [ ] Quality gates pass: `tofu fmt -check -recursive` on existing files

---

### US-023: Full quality gate sweep — validate and clean up entire codebase

**Description:** As a platform engineer, I want to run all quality gates across every module and environment in the repository and fix any remaining formatting, validation, lint, or Checkov issues, so that the codebase is in a clean, deployable state at the end of v4.

**Acceptance Criteria:**
- [ ] `tofu fmt -recursive` applied; resulting diff is zero (all files already correctly formatted)
- [ ] `tofu validate` exits 0 in all of: `bootstrap/`, `networking/hub-and-spoke/`, `modules/networking/`, `modules/avd/`, `modules/storage/`, `modules/monitoring/`, `modules/fslogix/`, `modules/aadds/`, `modules/dedicated/`, `modules/customer/`, `imaging/image-builder/`, `environments/shared/`, `environments/dedicated/`
- [ ] `tflint --recursive` exits 0 with 0 errors across the entire repository
- [ ] `checkov -d . --config-file checkov-config.yaml --compact` reports 0 unsuppressed critical/high findings; all suppressions have `#checkov:skip=CHECK_ID:justification` inline comments inside the resource block
- [ ] `modules/monitoring/main.tf`: verify no standalone `provider "azurerm"` block exists (child modules must not declare providers — only root modules may)
- [ ] Any child module that contains a top-level `provider` block has it removed
- [ ] `CHECKOV.md` suppressed checks register is up to date: all inline `#checkov:skip` annotations in the codebase have a corresponding entry in the register table
- [ ] All quality gates pass across the full repository

---

## Functional Requirements

- **FR-1 through FR-12**: Carried forward from v3 (all implemented in v1–v3)
- **FR-13:** AVD host pool registration token expiry must be ≤ 2 hours; tokens must be regenerated on each `tofu apply` run
- **FR-14:** Each of `modules/networking`, `modules/avd`, `modules/storage`, `modules/dedicated` must have at least one `.tftest.hcl` unit test file passing with mock providers (`tofu test` exits 0)
- **FR-15:** A dedicated App Attach Premium File Share must exist in `environments/shared/` and the `modules/avd` interface must expose `app_attach_type` and `app_attach_packages` variables
- **FR-16:** `modules/monitoring` must be wired into both shared and dedicated environments via `log_analytics_workspace_id` passed to `module.avd`, with AVD-specific metric alerts configured
- **FR-17:** Azure Firewall DNS proxy must be explicitly enabled (`proxy_enabled = true`) in the Firewall Policy in `networking/hub-and-spoke`
- **FR-18:** Five additional AVM modules evaluated and decisions recorded in `AVM.md`

---

## Non-Goals (Out of Scope)

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
- New architectural decisions beyond what is already recorded in `docs/architecture-decisions.md`

---

## Technical Considerations

- **`timeadd(timestamp(), "2h")` for token expiry:** This causes `azurerm_virtual_desktop_host_pool_registration_info` to show as "replace" on every `tofu plan`. This is expected and by design — document in ADR.
- **`--framework terraform` in Checkov:** The `--framework opentofu` flag is invalid. All Checkov commands must use `--framework terraform`. The `checkov-config.yaml` already handles this.
- **Mock provider syntax:** OpenTofu 1.7+ supports `mock_provider` in `.tftest.hcl`. All test stories assume OpenTofu ≥ 1.7.
- **Provider blocks in child modules:** `provider "azurerm" { features {} }` must NOT appear in child modules. US-023 checks for and removes any such blocks.
- **App Attach package registration:** `azurerm_virtual_desktop_application` does not natively support App Attach package registration via ARM. IaC handles storage and RBAC only; App Attach package registration is a post-deployment manual step documented in `docs/runbook-add-customer.md`.
- **AVM evaluation (US-021):** Documentation only — no AVM modules are adopted unless evaluation explicitly recommends adoption. Based on v2 findings, rejection is the expected outcome for most modules until they reach v1.0.

---

## Success Metrics

- `tofu validate` passes in all 13 root module / submodule directories with 0 errors
- `checkov` reports 0 unsuppressed critical/high findings across the entire repo
- `tofu test` exits 0 in `modules/networking/`, `modules/avd/`, `modules/storage/`, `modules/dedicated/`
- AVD host pool registration token expiry is ≤ 2 hours (no hardcoded future date)
- `modules/avd` exposes `app_attach_type` and `app_attach_packages` variables
- Monitoring module `log_analytics_workspace_id` is passed to `module.avd` in `environments/shared/`
- Azure Firewall DNS proxy `proxy_enabled = true` present in `networking/hub-and-spoke/main.tf`
- Five additional AVM modules evaluated and decisions recorded in `AVM.md`

---

## Dependency Order

Stories can be worked in parallel within a tier. Complete lower tiers before starting higher tiers.

| Tier | Stories | Notes |
|---|---|---|
| 1 — Foundation | US-022, US-023 | Token hardening + codebase cleanup; no cross-story dependencies |
| 2 — Implementation | US-015, US-016, US-017 | Networking DNS proxy, App Attach AVD vars, Monitoring wiring; US-015 should precede US-016 (DNS needed for session host connectivity) |
| 3 — Tests | US-018, US-019, US-020 | Unit tests depend on modules being clean (Tier 1 + 2 complete) |
| 4 — AVM Research | US-021 | Documentation only; can run in parallel with Tier 2 or 3 |