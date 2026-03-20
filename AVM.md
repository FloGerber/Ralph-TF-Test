# Azure Verified Modules (AVM) Evaluation

**Date evaluated**: 2026-03-19  
**Evaluator**: US-012 automation pass  
**Purpose**: Assess whether AVM modules for VNet, Storage Account, and AVD Host Pool reduce custom code and should be adopted into this codebase.

---

## Summary Table

| AVM Module | Version Evaluated | Decision | Reason |
|---|---|---|---|
| `azure/avm-res-network-virtualnetwork` | v0.17.1 | **REJECTED** | Extra providers required; structural mismatch; no RG creation; telemetry overhead |
| `azure/avm-res-storage-storageaccount` | v0.6.7 | **REJECTED** | Extra providers required; 1-account-per-call vs our multi-account pattern; version still pre-1.0 |
| `azure/avm-res-desktopvirtualization-hostpool` | v0.4.0 | **REJECTED** | Covers only host pool + registration info; our module is far richer (VMSS, app groups, scaling) |
| `azure/avm-res-keyvault-vault` | v0.10.2 | **REJECTED** | No current Key Vault footprint; extra providers; broad secret/key feature set would add unused surface area |
| `azure/avm-res-operationalinsights-workspace` | v0.5.1 | **REJECTED** | Extra providers required; workspace AVM scope exceeds our simple LAW pattern; pre-1.0 |
| `azure/avm-res-network-firewallpolicy` | v0.3.4 | **REJECTED** | Covers policy only; would split hub firewall management; extra providers; pre-1.0 |
| `azure/avm-res-managedidentity-userassignedidentity` | v0.5.0 | **REJECTED** | Wraps a single native resource; adds provider overhead without reducing custom code |
| `azure/avm-res-resources-resourcegroup` | v0.2.2 | **REJECTED** | Wraps a trivial native resource; adds provider overhead and module indirection only |

---

## Detailed Evaluations

### 1. `azure/avm-res-network-virtualnetwork` v0.17.1

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-network-virtualnetwork/azurerm/0.17.1`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork/tree/v0.17.1`

#### What it does
- Creates a VNet (via `azapi_resource.vnet`, not `azurerm_virtual_network`)
- Creates subnets (via `azapi_resource` sub-resources)
- Manages VNet peerings (supports bidirectional `create_reverse_peering`)
- Supports IPAM pool allocation (requires Azure Virtual Network Manager)
- Adds diagnostic settings, management locks, role assignments at VNet level

#### Why REJECTED

1. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, `random ~> 3.5` in addition to `azurerm ~> 4.0`. Our current lock file only contains `azurerm`. Adding three new providers increases supply-chain risk and lock-file churn.

2. **Uses `azapi_resource` instead of `azurerm_virtual_network`**: The AVM uses the low-level Azure REST API provider for the VNet resource. This makes state management and drift detection less transparent than the native azurerm resource. Checkov and tflint rules are written against `azurerm_virtual_network`, not azapi resources.

3. **No resource group creation**: Our `modules/networking` creates the resource group alongside the VNet. The AVM only takes `parent_id` (the resource group resource ID). This would require splitting RG creation out of the networking module and passing a dependency, touching all callers.

4. **Different subnet interface**: AVM uses a `map(object)` keyed by arbitrary key; our callers pass a `list(object)` with explicit `name` fields. Migration would touch every caller of `modules/networking`.

5. **Telemetry / modtm overhead**: The module sends usage telemetry to Microsoft via `modtm_telemetry`. While it can be disabled with `enable_telemetry = false`, it adds a provider dependency and extra state resources.

6. **Does not cover NSG or Firewall**: Our `modules/networking` also manages a shared NSG and an optional Azure Firewall. The AVM would only replace the VNet+subnet portion, leaving a split module that mixes AVM and native resources — adding complexity without reducing it.

7. **Version pre-1.0 (`v0.17.1`)**: The module maintainers' own README warns: "A module SHOULD NOT be considered stable till at least it is major version one (1.0.0)." Breaking changes are expected on any release.

#### Decision: REJECTED

Custom `modules/networking` is retained. It is already well-tested and correct. The AVM would add provider dependencies, break existing callers, and split NSG/firewall management across two different modules.

---

### 2. `azure/avm-res-storage-storageaccount` v0.6.7

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-storage-storageaccount/azurerm/0.6.7`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/tree/v0.6.7`

#### What it does
- Creates a single storage account with full configuration
- Manages blob containers, file shares, queues, tables via `azapi_resource`
- Manages private endpoints (managed and unmanaged DNS zone groups)
- Manages diagnostic settings, management locks, role assignments, CMK
- Supports RBAC assignments at account, container, share, queue, table level

#### Why REJECTED

1. **Pre-1.0 stability warning**: The README explicitly states the module is not stable until v1.0. At v0.6.7, breaking changes are expected between minor versions.

2. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, `random >= 3.5.0`, `time >= 0.9.0` — four additional providers beyond `azurerm`.

3. **One-account-per-call pattern vs our multi-account pattern**: Our `modules/storage` provisions multiple storage accounts in a single module call using `for_each` over `storage_account_config`. The AVM manages a single account per call. Migrating to AVM would require the callers (`environments/shared`, `modules/dedicated`) to be refactored to call the module once per storage account, significantly increasing configuration verbosity.

4. **File share management via azapi**: File shares are created via `azapi_resource.share` rather than `azurerm_storage_share`. This bypasses the standard azurerm resource, making tflint/Checkov analysis less effective.

5. **Scope creep for our use case**: The AVM includes blob containers, queues, tables, data lake filesystems, static websites — none of which we need. The added complexity provides no benefit for our FSLogix/App Attach FileStorage use case.

6. **Our existing module already implements security best practices**: `modules/storage` already enforces `https_traffic_only_enabled = true`, `public_network_access_enabled = false`, `local_user_enabled = false`, `min_tls_version = "TLS1_2"`, `default_action = "Deny"`, and private DNS zone group registration. The AVM would not add security value.

#### Decision: REJECTED

Custom `modules/storage` is retained. Our module is already secure, well-tested, and purpose-built for the FSLogix/App Attach FileStorage pattern. The AVM's multi-provider overhead and single-account-per-call pattern would increase configuration complexity without reducing custom code.

---

### 3. `azure/avm-res-desktopvirtualization-hostpool` v0.4.0

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-desktopvirtualization-hostpool/azurerm/0.4.0`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-desktopvirtualization-hostpool/tree/v0.4.0`

#### What it does
- Creates `azurerm_virtual_desktop_host_pool` + `azurerm_virtual_desktop_host_pool_registration_info`
- Manages private endpoints on the host pool
- Manages diagnostic settings and management locks
- Exposes role assignments at the host pool level

#### Why REJECTED

1. **Narrow scope**: The AVM covers only the host pool resource and registration token. Our `modules/avd` module additionally manages:
   - Application groups (`azurerm_virtual_desktop_application_group`)
   - Workspaces (`azurerm_virtual_desktop_workspace`)
   - Workspace-to-app-group associations
   - Scaling plans
   - AVD LoB application publishing
   - Orchestrated VMSS (Flexible) session hosts
   - User-assigned managed identities for VMSS
   - Domain join and DSC extension configuration
   - FSLogix RBAC assignments
   - Diagnostic settings for host pools and app groups

2. **Would not reduce custom code**: Wrapping just the host pool resource in AVM while keeping the rest custom would add a module call layer without reducing our own code. The net result is more complexity, not less.

3. **Registration token management**: The AVM exposes `registrationinfo_token` as a sensitive output. Our current pattern also generates a registration token inline. Adopting the AVM for this single resource would require threading a sensitive output through additional levels of the module hierarchy.

4. **Provider version alignment**: The AVM requires `azurerm >= 4.0.0, <5.0` which is compatible with our `~> 4.0` pin, but also requires `modtm ~> 0.3` (telemetry provider) and `random ~> 3.5`. The `modtm` provider is not currently in our lock file.

5. **Version pre-1.0 (`v0.4.0`)**: Same stability concern as the other modules.

#### Decision: REJECTED

Custom `modules/avd` is retained. The AVM covers only a tiny fraction of AVD functionality needed by this platform. Adopting it for the host pool resource alone would add provider overhead and module nesting without reducing the amount of custom code we maintain.

---

### 4. `azure/avm-res-keyvault-vault` v0.10.2

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-keyvault-vault/azurerm/0.10.2`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault/tree/v0.10.2`

#### What it does
- Creates an Azure Key Vault with RBAC or legacy access policy support
- Manages keys, secrets, certificate contacts, private endpoints, diagnostic settings, locks, and role assignments
- Adds optional waits around RBAC propagation for secret/key/contact operations
- Supports network ACLs, purge protection, and private DNS integration

#### Why REJECTED

1. **No current Key Vault footprint in this repo**: There is no `azurerm_key_vault` usage in the current codebase. Adopting the AVM would introduce a new abstraction before there is an actual platform requirement to replace.

2. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, `random ~> 3.5`, and `time ~> 0.9` alongside `azurerm`. That is four more providers than the repo currently uses for equivalent functionality.

3. **Scope is broader than our likely near-term need**: The module bundles secrets, keys, contacts, private endpoints, RBAC, and legacy access policies. If this platform later adds Key Vault, it is more likely to start with a narrow vault-for-secrets or CMK use case than the AVM's full management surface.

4. **Pre-1.0 stability warning**: Although mature relative to other AVMs here, it is still below v1.0.0 and therefore still carries the AVM breaking-change caveat.

5. **Would not remove existing custom code today**: Because there is no Key Vault module in this repo, adopting this AVM now would create new code paths rather than simplifying existing ones.

#### Decision: REJECTED

Do not introduce the AVM at this time. Revisit only if the platform gains a concrete Key Vault requirement such as CMK-backed storage, certificate storage, or centralized secret distribution.

---

### 5. `azure/avm-res-operationalinsights-workspace` v0.5.1

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-operationalinsights-workspace/azurerm/0.5.1`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-operationalinsights-workspace/tree/v0.5.1`

#### What it does
- Creates a Log Analytics workspace
- Manages linked services, linked storage accounts, tables, table updates, data exports, private endpoints, private link scopes, locks, and role assignments
- Supports workspace CMK, managed identity, network security perimeter association, and diagnostic settings
- Uses both native `azurerm_*` resources and several `azapi_*` resources for advanced workspace features

#### Why REJECTED

1. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, `random ~> 3.5`, and `time ~> 0.9` in addition to `azurerm`. Our current monitoring module does not need any of those providers.

2. **Much broader scope than our current monitoring pattern**: `modules/monitoring` currently provisions an optional Log Analytics workspace plus action groups, metric alerts, log-query alerts, and diagnostic settings. The AVM adds tables, data exports, private link scopes, NSP association, and linked services that this platform does not currently use.

3. **Would complicate an otherwise simple module boundary**: Our current module keeps workspace creation tightly coupled with alerting and diagnostic-setting consumers in a single module call. Replacing only the workspace with AVM would split responsibility across AVM and custom code without reducing the custom alerting logic we still need.

4. **AzAPI-heavy implementation reduces benefit for this repo**: The AVM uses multiple `azapi_resource` and `azapi_update_resource` resources for advanced features. This increases provider surface area and reduces the simplicity advantage of our current native `azurerm_log_analytics_workspace` usage.

5. **Version pre-1.0 (`v0.5.1`)**: Same AVM stability concern as the other candidates.

#### Decision: REJECTED

Custom `modules/monitoring` is retained. The platform only needs a straightforward workspace resource today, while the AVM would add providers and advanced features that do not offset the migration cost.

---

### 6. `azure/avm-res-network-firewallpolicy` v0.3.4

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-network-firewallpolicy/azurerm/0.3.4`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-network-firewallpolicy/tree/v0.3.4`

#### What it does
- Creates an Azure Firewall Policy
- Supports DNS proxy, insights, intrusion detection, explicit proxy, threat intelligence settings, TLS certificate, locks, diagnostics, and role assignments
- Exposes optional user-assigned identity wiring for the policy

#### Why REJECTED

1. **Covers only the policy, not the firewall deployment around it**: In `networking/hub-and-spoke`, the policy is tightly paired with `azurerm_firewall`, public IP, subnet wiring, and shared-network resource group creation. Swapping in AVM for only the policy would split one cohesive hub-firewall implementation across two abstractions.

2. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, and `random ~> 3.5` in addition to `azurerm`.

3. **No reduction in rule-management complexity**: This AVM manages the firewall policy resource itself, but our repo still must manage the actual firewall instance and surrounding network topology. It would reduce very little custom code.

4. **Root-level hub-and-spoke stack already expresses the required features clearly**: The current implementation already sets Premium SKU, `threat_intelligence_mode = "Deny"`, `dns { proxy_enabled = true }`, and `intrusion_detection { mode = "Deny" }` directly in a single resource. The AVM does not simplify that configuration materially.

5. **Version pre-1.0 (`v0.3.4`)**: Same stability concern as the other AVMs.

#### Decision: REJECTED

Keep the native `azurerm_firewall_policy` resource in `networking/hub-and-spoke` and `bootstrap`. The current code is already concise, and AVM adoption would add providers and a split control surface without meaningful payoff.

---

### 7. `azure/avm-res-managedidentity-userassignedidentity` v0.5.0

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-managedidentity-userassignedidentity/azurerm/0.5.0`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-managedidentity-userassignedidentity/tree/v0.5.0`

#### What it does
- Creates a user-assigned managed identity
- Supports optional federated identity credentials, management locks, and role assignments
- Exposes client ID, principal ID, tenant ID, and resource object outputs

#### Why REJECTED

1. **Wraps a single native resource we already use directly**: The current codebase creates user-assigned identities in `modules/avd` and `imaging/image-builder` with straightforward `azurerm_user_assigned_identity` resources. The AVM would mostly wrap that same primitive.

2. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, and `random ~> 3.5` in addition to `azurerm`.

3. **Does not remove surrounding role-assignment logic**: In both current usages, the interesting behavior is the follow-on RBAC and consumer resource wiring, not the identity resource itself. The AVM would still leave most of that code in place.

4. **Module indirection is harder to justify for small, repeated primitives**: Naming, location, resource group, and tags are already one-screen native resources in this repo. Replacing them with an AVM call would make those paths less transparent without materially increasing consistency.

5. **Version pre-1.0 (`v0.5.0`)**: Same stability concern as the other AVMs.

#### Decision: REJECTED

Retain direct `azurerm_user_assigned_identity` usage. The resource is already simple enough that an AVM wrapper would add provider overhead and indirection without reducing maintenance cost.

---

### 8. `azure/avm-res-resources-resourcegroup` v0.2.2

**Registry**: `https://registry.terraform.io/modules/azure/avm-res-resources-resourcegroup/azurerm/0.2.2`  
**GitHub**: `https://github.com/Azure/terraform-azurerm-avm-res-resources-resourcegroup/tree/v0.2.2`

#### What it does
- Creates a resource group
- Supports optional management lock and role assignments
- Exposes resource group name, location, ID, and full resource output

#### Why REJECTED

1. **Wraps a trivial native resource**: The codebase already creates resource groups directly in multiple places (`modules/networking`, `modules/customer`, `modules/aadds`, `imaging/image-builder`, `bootstrap`, and `networking/hub-and-spoke`). Each usage is only a few lines of plain `azurerm_resource_group` configuration.

2. **Additional provider dependencies**: Requires `azapi ~> 2.4`, `modtm ~> 0.3`, and `random ~> 3.5` even though the underlying task is just creating a resource group.

3. **Would add module-call noise everywhere**: Because resource groups are foundational objects, adopting this AVM would introduce many small module invocations across the repo for almost no functional gain.

4. **Current callers often create more than just the RG**: In this repo, resource-group creation usually sits next to tightly related resources inside the same module. Extracting RG creation to AVM would fragment those modules and increase dependency wiring.

5. **Version pre-1.0 (`v0.2.2`)**: Same stability concern as the other AVMs.

#### Decision: REJECTED

Retain direct `azurerm_resource_group` resources. Resource groups are too simple and too pervasive in this codebase for this AVM to justify the extra providers and abstraction layer.

---

## Conclusion

All eight evaluated AVMs are **rejected** for this codebase at this time. The primary blocking factors are:

1. **Additional provider requirements** (`azapi`, `modtm`, `random`, `time`) — every newly evaluated AVM introduces providers not currently required for the equivalent native resources in this repo.
2. **Pre-1.0 stability** — all eight evaluated AVMs remain below v1.0.0 and explicitly carry a breaking-change warning.
3. **Interface mismatches** — several AVMs do not align with our current caller patterns and would require non-trivial refactoring across environment and module boundaries.
4. **Narrow or uneven scope** — some AVMs cover only one layer of a broader module (`hostpool`, `firewallpolicy`) and would split management across AVM and custom code.
5. **Low-value wrappers for simple primitives** — the managed identity and resource group AVMs mostly wrap very small native `azurerm` resources that are already clearer to manage directly in this repo.
6. **No current workload to replace** — the Key Vault AVM is mature enough to watch, but there is no existing Key Vault implementation in this codebase for it to simplify yet.

### Recommendation for Future Review

Re-evaluate when:
- AVM modules reach v1.0.0 (stable API guarantee)
- The `azapi` provider is already required by other modules in this codebase
- A new environment layer is being built from scratch (no migration cost)
- AVM for VNet includes NSG and optional firewall management
- The platform introduces a concrete Key Vault requirement (for example CMK, secret distribution, or certificate storage)
- The monitoring stack starts needing advanced Log Analytics features already packaged by AVM (tables, AMPLS, data exports, private link scope)
- Managed identity or resource group provisioning becomes complex enough that a wrapper would replace repeated RBAC/lock patterns rather than a single native resource

---

*This document should be updated when new AVM versions are released or when the codebase architecture changes.*
