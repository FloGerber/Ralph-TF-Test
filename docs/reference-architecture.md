# Reference Architecture — Azure Virtual Desktop Platform

This document describes the approved end-to-end reference architecture for the AVD platform implemented in this repository. It maps deployment models, topology, tenant/subscription boundaries, landing zone layers, and AVM pattern/resource module responsibilities to the code layout so implementers and automation follow a single, auditable design.

1) Platform overview
- The platform is a Hub-and-Spoke landing zone built as multiple independent root modules (separate OpenTofu/terraform roots). See `ADR-006` in `docs/architecture-decisions.md` for rationale.
- Primary logical concerns: Identity, Connectivity (Hub), Shared AVD service, Dedicated customer AVD environments, Management/Observability, and Imaging.

2) Deployment models
- Platform (shared services): centralized services that are shared across multiple customers — identity (AADDS), Azure Firewall, DNS, shared image gallery, monitoring, and pipelines. Code roots: `bootstrap/`, `networking/hub-and-spoke/`, `imaging/image-builder/`, `modules/aadds`.
- Shared AVD (multi-tenant pooled RemoteApp): a single Shared host-pool that hosts multiple customers' RemoteApp sessions (pooled, breadth-first). Code roots: `environments/shared/`, `modules/avd` (shared configuration).
- Dedicated AVD (per-customer isolated): dedicated Personal/Desktop host pools and per-customer infrastructure. Each dedicated customer is instantiated as a module instance under `environments/dedicated/` (see `environments/dedicated/customer-example.tf`). Dedicated customers get per-customer storage and VNets.

3) Topology — Hub-and-Spoke
- Hub: central region-level services (Azure Firewall, AADDS subnet, private DNS zones, shared private endpoints). Implemented by `networking/hub-and-spoke/` and `modules/aadds`.
- Spokes: two spoke types are defined:
  - Shared spoke: hosts the shared AVD session hosts and associated private endpoints — `environments/shared/`.
  - Dedicated spoke (per-customer): each dedicated customer gets their own spoke VNet, NSG, and routing pointing to the hub firewall — `environments/dedicated/`.
- VNets are peered (spoke-to-hub and hub-to-spoke reverse peering) and DNS forwarding is performed via the hub firewall (see `ADR-010`).

4) Tenant and subscription boundaries
- Tenant boundary: a single Microsoft Entra ID tenant is assumed for the platform. All subscriptions used by the platform exist under the same tenant (service principal and role assignments operate within this tenant).
- Subscription boundaries: recommended subscription split (logical examples reflected in the diagram `Reference_Architecture.jpg`):
  - Identity subscription — hosts AADDS resources and their subnet (`modules/aadds`).
  - Connectivity subscription — hub networking, firewall, private DNS, peering (`networking/hub-and-spoke`).
  - Shared AVD landing zone subscription — shared host pool, shared image gallery, shared storage for common artifacts (`environments/shared`, `imaging/image-builder`).
  - Management subscription — observability, Log Analytics, automation accounts, update management (`docs/architecture-decisions.md` ADRs describe monitoring choices).
  - Customer (Dedicated) subscriptions — each dedicated customer environment is deployed into its own subscription (see below).

5) Dedicated customer subscription model (explicit requirement)
- Dedicated customer environments MUST be deployed into separate subscriptions that reside in the same Entra ID (tenant). This provides subscription-level isolation (billing, RBAC, quotas) while allowing the platform's centralized identity and connectivity services in the shared tenant to be consumed.
- Reference code: `environments/dedicated/customer-example.tf` demonstrates how per-customer module inputs accept hub/identity outputs (hub VNet ID, firewall IP, AADDS DNS IPs, private DNS zone ids). See `docs/runbook-add-customer.md` for operational details.

6) Landing zone layers (code ↔ concept mapping)
- Bootstrap: `bootstrap/` — backend, provider/bootstrap resources (initial state infrastructure).
- Networking / Hub-and-Spoke: `networking/hub-and-spoke/` — hub VNet, firewall, private DNS, peering.
- Identity: `modules/aadds` invoked from appropriate environment roots — AADDS in hub VNet.
- Imaging: `imaging/image-builder/` — image templates and gallery definitions (shared image gallery used by both Shared & Dedicated hosts).
- Environments: `environments/shared/`, `environments/dedicated/` — independent root modules for runtime resources (host pools, VMSS, storage accounts, private endpoints).
- Modules: reusable components live under `modules/` (e.g. `modules/avd`, `modules/customer`, `modules/aadds`, `modules/avd`).

7) AVM Pattern Modules and Resource Modules mapping
This platform does not adopt AVM modules wholesale (see `AVM.md`). The architecture explicitly maps the platform components to AVM patterns and, where an AVM resource exists, shows the equivalent repository module that implements the solution.

- Networking pattern
  - Intended AVM pattern: virtual network / hub-and-spoke pattern (AVM pattern: network VNet + peering)
  - Implemented by: `networking/hub-and-spoke/` and `modules/networking` (VNet, subnets, NSG, firewall)
  - If adopting AVM resource: `azure/avm-res-network-virtualnetwork` would correspond to `modules/networking` (note: AVM was evaluated and rejected — see `AVM.md`).

- Identity pattern
  - Intended AVM pattern: managed domain / identity
  - Implemented by: `modules/aadds` and invoked from hub/networking layer
  - Equivalent AVM resource (evaluated): `azure/avm-res-resources-resourcegroup` / (no direct AADDS AVM exists). We retain `modules/aadds` implementation.

- Compute / AVD pattern
  - Intended AVM pattern: desktop virtualization hostpool / scaling
  - Implemented by: `modules/avd` (host pools, app groups, workspaces, scaling plans, Flexible VMSS, session host registration flows)
  - Equivalent AVM resource: `azure/avm-res-desktopvirtualization-hostpool` — maps to `modules/avd` (AVM evaluated and rejected because it covers only hostpool surface; our module implements host pool + VMSS + app groups + scaling plans).

- Storage pattern (FSLogix profile storage)
  - Intended AVM pattern: storage account + private endpoint
  - Implemented by: `modules/premium_storage` or `modules/storage` (per-customer Premium FileStorage accounts, private endpoints, DNS zone groups)
  - Equivalent AVM resource: `azure/avm-res-storage-storageaccount` — maps to `modules/storage` (AVM rejected due to single-account-per-call pattern and provider overhead).

- Monitoring / Logging pattern
  - Implemented by: `modules/monitoring` and `management` roots (Log Analytics workspace, alerts)
  - Equivalent AVM resource: `azure/avm-res-operationalinsights-workspace` (evaluated, rejected due to scope/provider reasons).

- Security & Firewall policy pattern
  - Implemented by: `networking/hub-and-spoke/` (Azure Firewall and policy management)
  - Equivalent AVM resource: `azure/avm-res-network-firewallpolicy` (AVM evaluated and rejected — we keep policy + firewall in a single cohesive implementation).

Mapping summary: when an AVM resource would map neatly to a repo module, the mapping is recorded here for traceability. The repo currently prefers native `azurerm` implementations in `modules/` due to provider surface area, caller interfaces, and stability concerns (see `AVM.md`).

8) Operational constraints & deployment order
- Root modules are independent; deployment order must be followed: `bootstrap` → `networking/hub-and-spoke` → `imaging/image-builder` → `environments/shared` → `environments/dedicated`.
- AADDS provisioning is a two-pass process (deploy networking first with empty AADDS DNS IPs, provision AADDS, then re-apply networking to inject DNS server IPs). See `ADR-003` and `ADR-010` in `docs/architecture-decisions.md`.

9) Security, governance and checks
- Checkov, pre-commit, and CI are configured (see `.pre-commit-config.yaml`, `.github/workflows/checkov.yml`, and `checkov-config.yaml`). The project enforces `--framework terraform` for Checkov (see `docs/architecture-decisions.md` ADR-005).

10) Files & artifacts to reference
- Architecture decisions: `docs/architecture-decisions.md`
- AVM evaluation: `AVM.md`
- Runbook (onboarding): `docs/runbook-add-customer.md`
- Example dedicated customer: `environments/dedicated/customer-example.tf`
- Shared environment: `environments/shared/` root
- Topology diagram: `Reference_Architecture.jpg`

11) Validation commands (run locally)
- tofu fmt -check
- tofu validate
- terraform test  # run from each root that contains tests
- checkov -d . --framework terraform

If any of the above checks fail locally, follow the repository guidance and fix failing lint/tests before merging documentation or code changes.

---

Document history
- Created: 2026-03-20 — initial reference architecture aligned to repository layout and ADRs.
