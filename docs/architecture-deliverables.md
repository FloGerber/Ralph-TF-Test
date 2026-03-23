# Architecture Deliverables — Implementation Guidance

This document gathers the canonical architecture deliverables required to implement the AVD platform from this repository. It is an implementation-first, checklist-driven reference that points to source artefacts (design docs, diagrams, module mappings and CI guidance) so implementers have no hidden assumptions.

## Required Deliverables (what implementers must review)
- Topology & reference diagram: `Reference_Architecture.jpg` and `docs/reference-architecture.md`
- FSLogix design: `docs/fslogix.md`
- App Attach design: `docs/app-attach.md`
- IAM / security model: `docs/identity.md` and `BACKEND.md` (state & OIDC guidance)
- Module structure and mapping: `docs/reference-architecture.md` (AVM mappings) and `modules/` folder
- CI/CD design and gating: `.github/workflows/ci-cd.yml`, `docs/testing-strategy.md`, and `docs/onboarding.md`

## Purpose
- Keep one discoverable deliverable (`docs/architecture-deliverables.md`) that points implementers to authoritative artefacts in the repo and documents critical deployment ordering, validation commands, and AVM adoption decisions.

## Topology & Diagrams
- Topology: Hub-and-Spoke (see `Reference_Architecture.jpg`). The reference architecture document (`docs/reference-architecture.md`) explains subscription split, hub services, and spoke types (shared and dedicated).
- Use the diagram and the `Landing zone layers` mapping in `docs/reference-architecture.md` to plan deployment order and networking prerequisites.

## FSLogix (where to find and what to verify)
- Design doc: `docs/fslogix.md` — provision Premium FileStorage, one `profiles` share per customer, private endpoints, and AADDS/hybrid AD dependency.
- Verify: private endpoint DNS records exist, AADDS is available before FSLogix mounts are used, required RBAC roles assigned to session host identities.

## App Attach
- Design doc: `docs/app-attach.md` — packaging layout, staging→production promotion flow, storage layout for packages and manifests.
- CI: pipelines must be able to write to the staging share (runner in platform VNet or SAS/managed identity with private endpoint access).

## IAM / Security Model
- Implementation docs: `docs/identity.md` and `BACKEND.md` (backend/OIDC guidance). The repository uses a group-based assignment pattern (per-customer groups) and OIDC for pipeline identities.
- Verify: per-customer groups exist, role assignments for session host identities to storage shares, Key Vault policies for DEKs used by client-side encryption.

## Module Structure and AVM Mapping
- Canonical module locations: `modules/` (resource modules), `networking/`, `imaging/`, `environments/shared/`, `environments/dedicated/`.
- AVM pattern decision: the repository documents AVM evaluation and intentionally prefers native `azurerm` modules where AVM introduces provider complexity or insufficient surface area. The primary mappings are:
  - Networking: repo `networking/hub-and-spoke/` / `modules/networking`  ← AVM pattern `azure/avm-res-network-virtualnetwork` (evaluated, not adopted)
  - Identity: `modules/aadds`  ← no direct AVM equivalent (retain native)
  - Compute/AVD: `modules/avd`  ← AVM resource `azure/avm-res-desktopvirtualization-hostpool` (AVM covers hostpool only; repo implements hostpool+VMSS+app-groups)
  - Storage (FSLogix & App Attach): `modules/storage` / `modules/fslogix`  ← AVM resource `azure/avm-res-storage-storageaccount` (not adopted)
  - Monitoring: `modules/monitoring`  ← AVM `azure/avm-res-operationalinsights-workspace` (evaluated, not adopted)

State the principle: if an AVM resource maps neatly and is stable, it is recorded in `AVM.md`; otherwise the repository prefers small, single-responsibility native modules in `modules/`.

## Shared vs Dedicated models (what differs)
- Shared model: `environments/shared/` — shared workspace and host-pool, per-customer app groups and per-customer FSLogix shares on shared storage accounts (see `docs/fslogix.md` and `environments/shared/`).
- Dedicated model: `environments/dedicated/` and `modules/dedicated` — one subscription per dedicated customer, per-customer VNet, storage account and host-pool. Example invocation: `environments/dedicated/customer-example.tf`.

## CI/CD design and validation gates
- Primary CI: `.github/workflows/ci-cd.yml` implements the selector job that reads onboarding manifests and chooses target roots (bootstrap/shared/dedicated).
- Recommended job sequence:
  1. Selector (parses manifest)
  2. Formatting & lint: `tofu fmt -check`, tflint
  3. Validate: `tofu validate`
  4. Unit tests: `tofu test` / `terraform test` for roots/modules with tests
  5. Security scan: `checkov -d . --framework terraform`
  6. Plan: produce encrypted plan artifact (client-side DEK from Key Vault)
  7. Gated apply: manual approval for production `main` branch
- Reference: `docs/testing-strategy.md` for tftest patterns and where mock providers are used.

## Deployment order (implementation checklist)
1. `bootstrap/` — remote backend, management group baseline, Log Analytics workspace
2. `networking/hub-and-spoke/` — hub VNet, firewall, private DNS
3. `modules/aadds` / identity — AADDS provisioning (two-pass where required)
4. `imaging/image-builder/` — publish golden images to Shared Image Gallery
5. `environments/shared/` — shared AVD host-pool and per-customer FSLogix shares
6. `environments/dedicated/` — per-customer dedicated landing zones

## Validation commands (run in CI)
- tofu fmt -check
- tofu validate
- terraform test  # run per-root with tests
- checkov -d . --framework terraform

## Implementation notes and non-obvious assumptions
- All pipelines must run in an environment that has network access required to validate private endpoint-backed storage and must include `tofu`, `terraform` (if used), and `checkov`.
- FSLogix requires AADDS or hybrid AD DS before SMB mounts are attempted — this is a hard requirement.
- The repo intentionally avoids blind AVM adoption; decisions and mappings are recorded to avoid hidden assumptions during implementation.

## Where to find the source artefacts
- docs/reference-architecture.md
- docs/fslogix.md
- docs/app-attach.md
- docs/identity.md
- docs/testing-strategy.md
- docs/onboarding.md
- Reference_Architecture.jpg

---

Document history
- Created: 2026-03-20 — aggregate deliverable to satisfy US-016 and provide a single implementation entry point.
