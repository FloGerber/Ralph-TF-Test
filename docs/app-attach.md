App Attach Storage And Release Model

Overview
- App Attach packages (MSIX/App Attach VHDs) are stored in a dedicated Azure Files Premium share named `appattach` in the shared spoke for shared-host-pool deployments. Dedicated customer deployments may optionally include an `appattach` share on the customer's Premium FileStorage account (see `modules/dedicated` `appattach_quota_gib`).

Repository & Storage wiring
- Shared model: `environments/shared/locals.tf` defines `appattach_storage_account` and `appattach_file_share` and `environments/shared/main.tf` provisions the file share via `modules/storage` (`module.premium_storage`). Session host VMSS managed identities are granted `Storage File Data SMB Share Contributor` on the `appattach` storage account (see `resource "azurerm_role_assignment" "shared_appattach_session_hosts"`).
- Dedicated model: `modules/dedicated` can create an `appattach` file share on the customer's Premium account when `appattach_quota_gib > 0` (see `modules/dedicated/main.tf`).
- Storage module: `modules/storage` provisions Premium FileStorage accounts, file shares, private endpoints, network rules and RBAC assignments. It is the single source-of-truth for file share provisioning.

Packaging, staging, versioning, and promotion flow
- Directory layout (recommended):
  - On production share (read-only for hosts): `/packages/<app-name>/v<semver>/...` and `/manifests/<app-name>.json`
  - On staging share (private to CI/test): `/staging/<app-name>/v<semver>/...`
- Package metadata (manifest) format (example):
  {
    "name": "lob-app",
    "version": "1.2.0",
    "path": "\\\\stsharedappattach.file.core.windows.net\\appattach\\packages\\lob-app\\v1.2.0\\lob-app.msix",
    "compat": {
      "os": "Win11-23H2-msisc",
      "avd_agent": ">=1.0"
    }
  }
- Promotion flow (automated via CI/CD):
  1. Build/package: CI builds the MSIX/App Attach artifacts and stores them in a job artifact.
  2. Upload to staging share: CI uploads to the staging share (or a staging prefix on the same share) using a short-lived SAS or managed identity run inside the VNet (recommended). Use `az storage file upload` / `azcopy` or server-side copy operations.
  3. Validate: Run integration tests against a test AVD application group/hostpool that mounts the staging package.
  4. Promote: After validation, CI copies the package to the production path (`/packages/<app>/v<semver>/`) and updates the repository manifest file describing the published package (in `manifests/` or an environment-level TF variable file). Commit + PR triggers `tofu plan`/`tofu apply` to update the AVD configuration.
  5. Housekeeping: Keep older versions for rollback; optionally apply lifecycle retention policy on the storage account.

Security & access considerations
- Private endpoints: All App Attach storage uses `public_network_access_enabled = false`. Access from session hosts is via Private Endpoints (see `modules/storage` private endpoint support) and proper Private DNS records.
- Authentication: Session hosts use their user-assigned managed identities and are assigned `Storage File Data SMB Share Contributor` on the appattach account. CI should use short-lived SAS tokens or run in a trusted pipeline environment with a managed identity that has scoped storage access.
- Avoid mounting with storage account keys in production; use Azure AD Kerberos / managed identity based mounting where supported.

Integration points with AVD application groups
- Application delivery: The AVD control plane (application groups / workspaces) is the distribution mechanism for published applications. The repository exposes `modules/avd` inputs `app_attach_packages` (list of {name,path}) and `app_attach_type` to enable App Attach semantics. The workflow is:
  - CI publishes package and updates manifest
  - Terraform variable or module input `app_attach_packages` is updated to reference the package path (the manifest can be rendered into a TF var file)
  - `tofu apply` updates AVD resources (or associated metadata) so that the host/agent mounts the package at next activation window or host restart depending on delivery mechanism.
- Application groups: Application groups remain the logical container for published apps. For MSIX/App Attach, package mounting is a host-level operation; application group metadata (friendly name, command-line) continues to live in `modules/avd` `application_group_config` and `lob_application_config`.

Rollout strategy (minimal manual work)
- Canary & staged promotion: Use a canary hostpool/application group in the shared environment or a dedicated test customer. Promotion pipeline targets staging first, runs smoke tests, then promotes to production. This avoids manual copy and manual approval gates can be added to CI for business approvals.
- Declarative promotion: Promotion is a single repository change (manifest update + optional TF var file) that CI applies. The Terraform change only updates inputs (package path/version) — no imperative custom scripts are required once upload & copy are automated.
- Automated role assignment: The repository already ensures session hosts have SMB role access to the appattach share; no manual RBAC changes required during package rollout.

Shared vs Dedicated applicability
- Shared model (recommended for RemoteApp pooled host pools): One central `appattach` Premium Files share holds packages used by all customers in the shared host pool. Pros: simplified package management, single place to maintain versions, smaller storage footprint. Cons: package isolation between customers is logical — ensure licensing and tenant separation concerns are addressed.
- Dedicated model (recommended for strict isolation): Create an `appattach` share per-customer (via `modules/dedicated` `appattach_quota_gib`) if customer requires full data isolation or unique packages. Pros: isolation and per-customer lifecycle. Cons: operational overhead and duplicate packages across customers.

Operational recommendations
- Use semantic versioning (semver) for packages and keep immutable production paths (never overwrite a `vX.Y.Z` path). Promote by adding new version directories and updating manifests.
- CI runs should be colocated to the platform VNet (or use pipeline agents with VNet integration) to access private endpoints without exposing storage publicly.
- Use `azcopy` for large artifacts and `az storage file copy` when cross-account server-side copy is preferred.
- Maintain package manifests in the repo under `manifests/` so promotion is a single PR that can be reviewed and audited.

References
- environments/shared/locals.tf — appattach storage account & share definition
- environments/shared/main.tf — role assignments for session host identities on appattach
- modules/storage — provisioning of Premium FileStorage, private endpoints, and RBAC
- modules/avd — `app_attach_packages` input and `app_attach_type` flag
