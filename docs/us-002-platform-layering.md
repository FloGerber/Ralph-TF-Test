# US-002: Platform Layering and Repository Structure

This document defines the recommended OpenTofu repository layout and platform layering so platform and workload code remain composable and DRY.

Layers
-
- `bootstrap/`
  - Purpose: perform one-time bootstrap tasks needed to provision the platform (state backends, remote state buckets, service principals, management groups, provider registrations, and any CI/CD/service accounts).
  - Inputs: administrative credentials, management tenant id, org root subscription id, bootstrap configuration (region, naming prefix).
  - Outputs: remote state endpoints (backend connection info), bootstrap-created identities and secrets (references, not raw secrets), storage account/container names, state locking resource ids.
  - Dependency order: first — nothing depends on it.

- `platform/`
  - Purpose: core platform infrastructure shared across landing zones — management networking (hub), identity services (AAD groups, role assignments), policy, logging/monitoring, shared KeyVaults, and foundational shared services (e.g. AVD shared resources used by multiple tenants).
  - Inputs: remote state/backends (from `bootstrap/`), subscription ids, tenant metadata, policy definitions, allowed locations.
  - Outputs: hub VNet/subnet ids, shared service endpoints, policy assignment ids, shared KeyVault ids, logging workspace ids.
  - Dependency order: after `bootstrap/`, before any landing zone.

- `landingzones/shared-avd/`
  - Purpose: landing zone pattern that hosts shared Azure Virtual Desktop (AVD) resources that can serve multiple tenants/workloads (central hostpools, image galleries). Reuses `modules/avd` and `modules/networking`.
  - Inputs: hub/shared networking outputs (VNet/subnet ids) from `platform/`, image gallery ids, AVD configuration variables (host pool sizing, vm sku), identity/principal ids.
  - Outputs: hostpool ids, gallery image ids, VM scale set ids, network interface ids (if required), AVD-related role assignment ids.
  - Dependency order: after `platform/`.

- `landingzones/dedicated-avd/`
  - Purpose: landing zone pattern that provisions isolated AVD per tenant/subscription or per business unit. Shares common modules with `shared-avd` to avoid duplication.
  - Inputs: landing zone specific subscription id, platform outputs (shared services) as needed, per-tenant configuration (naming, size, ip ranges).
  - Outputs: per-tenant hostpools, VM resources, networking objects local to the subscription.
  - Dependency order: after `platform/`. Can run in parallel across different subscriptions.

- `modules/` (reusable workload & resource modules)
  - Purpose: house composable Terraform/OpenTofu modules used by both platform and landingzones (e.g. `modules/avd`, `modules/networking`, `modules/keyvault`, `modules/logging`, `modules/aadds`, `modules/role-assignments`).
  - Inputs: module-specific variables (naming, sku, configuration) passed from higher layer stacks.
  - Outputs: module-specific ids and attributes consumed by dependent stacks.
  - Dependency order: referenced by `platform/` and `landingzones/*`.


Design principles and dependency ordering
-
- Clear dependency chain: `bootstrap/` -> `platform/` -> `landingzones/{shared,dedicated}/` -> workload composition using `modules/`.
- Landing zones must not duplicate module logic — they should call modules from `modules/` and pass configuration to them.
- Shared vs Dedicated: both landing zone patterns should consume the same modules with different variables. For example, `landingzones/shared-avd/` passes a `shared=true` variable to `modules/avd` while `landingzones/dedicated-avd/` passes `shared=false` and tenant-specific variables.
- Bootstrap concerns are strictly about environment setup and remote state; they do not contain workload resources. Keep bootstrapping limited, auditable, and safe to re-run (idempotent).
- Workload concerns live in landing zones and modules; they depend on outputs from platform and never reach back into bootstrap state.


Inputs and outputs (example variables)
-
- Common inputs passed down the stack: `tenant_id`, `subscription_id`, `location`, `naming_prefix`, `tags`, `backend_config`.
- Typical platform outputs consumed by landing zones: `hub_vnet_id`, `hub_subnet_ids`, `log_analytics_workspace_id`, `shared_keyvault_id`, `shared_identity_principal_id`.


Reuse and DRY patterns
-
- Keep resource definitions inside `modules/` and reference them; do not redefine core resources across landing zones.
- Use small focused modules (single responsibility): e.g. `modules/networking` returns `vnet_id` and `subnet_ids`; `modules/avd` returns `hostpool_id`, `application_group_id`.
- Provide wrapper stack modules under `landingzones/` that configure and compose reusable modules rather than embed resource creation.


Repository layout (recommended)
-
- `bootstrap/` — remote state and initial infra
- `platform/` — core shared platform stacks
- `landingzones/`
  - `shared-avd/` — composition that configures shared AVD
  - `dedicated-avd/` — composition that configures dedicated AVD per tenant
- `modules/` — reusable modules (avd, networking, keyvault, logging, aadds, role-assignments, etc.)
- `examples/` — example usage and troubleshooting
- `docs/` — architecture and PRD docs (this file)


Validation and quality checks
-
- Recommended local checks (run from repo root):

```
tofu fmt -check
tofu validate
terraform init -backend-config="$(cat bootstrap/backend-config.tfvars | sed -n '1p')" # example
terraform validate
terraform test
checkov -d .
```

Notes: CI should run `tofu fmt -check`, `tofu validate`, `terraform init/validate`, `terraform test`, and `checkov -d .` for policy checks. If any of those tools are not available in the dev machine, run them in a CI container with OpenTofu/Terraform and Checkov installed.


References
-
- See `docs/reference-architecture.md` for topology and AVM mapping notes.
