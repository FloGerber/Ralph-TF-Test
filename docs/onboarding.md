# Git-driven Customer Onboarding

This document describes the repository-driven onboarding model: manifests live in Git and are the source of truth for creating either shared or dedicated customer deployments.

Source of truth
- Place manifests under `onboarding/manifests/<shared|dedicated>/` as JSON files named `customer-<slug>.json`.
- A JSON Schema lives at `onboarding/schema/onboarding.schema.json` and CI uses it to validate manifests.

Required fields
- Common (required for all customers):
  - `customer_name` (string) — unique short slug used in resource naming and folder names.
  - `display_name` (string) — human-friendly name.
  - `environment` (string) — `shared` or `dedicated`.
  - `contact_email` (string, email) — primary contact for onboarding.
  - `location` (string) — Azure region for resources.
  - `tags` (object) — map of tags applied to created resources.

- Shared-model (additional required/semantics):
  - `workspace_id` (string) — resource id of the shared AVD workspace to assign the customer to.
  - `customer_entra_group_object_id` (string, optional) — Entra group object id used for role assignments (leave empty to skip).
  - `fslogix_profile_share` (string) — name of the FSLogix share to allocate for the customer.

- Dedicated-model (additional required/semantics):
  - `subscription_id` (string) — customer subscription where the dedicated landing zone will be deployed.
  - `hub_vnet_id` (string) — hub vnet resource id used for connectivity.
  - `avd_image_id` (string, optional) — golden image version id to use (can be updated later).
  - `user_count` (integer) — initial user seat estimate for sizing.

Validation rules
- Manifests are validated using `onboarding/schema/onboarding.schema.json` (JSON Schema draft-07 compatible). CI job runs `jq`/`ajv` or native validator to fail the PR on invalid manifests.
- Semantic checks (implemented in CI scripts):
  1. `customer_name` must be lowercase alphanumeric and `-` only, max 32 chars.
  2. `environment` must be `shared` or `dedicated` and the file must live in the matching folder (`onboarding/manifests/shared/` or `.../dedicated/`).
  3. If `environment` is `dedicated`, `subscription_id` must be present and must match a subscription id pattern.
  4. If `environment` is `shared`, `workspace_id` must be present and must look like a resource id.

Onboarding flow & pipeline consumption points
- Typical GitOps flow:
  1. Developer/Operator creates `onboarding/manifests/<env>/customer-<slug>.json` and opens a PR.
  2. CI runs manifest schema validation, `tofu fmt -check`, `tofu validate` for the impacted roots, `terraform test` for modules where tests exist, and `checkov -d .` for policy checks. PR must pass these checks before merge.
  3. On merge, the pipeline identifies the environment from the manifest and triggers the appropriate pipeline path:
     - Shared path: triggers `environments/shared/` pipeline that consumes the manifest to create per-customer app group assignments, FSLogix storage references, and RBAC entries.
     - Dedicated path: triggers `environments/dedicated/` pipeline which creates/updates a module block (or substitutes variables) that invokes `modules/dedicated` with the manifest values (noting `subscription_id` selects remote backend and applies into the customer's subscription workspace).
  4. Pre-apply stage: pipeline resolves secrets/credentials referenced by the manifest (e.g., domain join credentials) via Key Vault or CI secret store; no plaintext secrets should be committed to manifests.
  5. Apply stage: runs `tofu apply` (or Terraform apply) in the correct working directory with generated varfiles derived from the manifest.

Deployment paths
- Shared customers: manifests in `onboarding/manifests/shared/` are consumed by the shared landing zone pipeline which uses `modules/customer` to create RBAC, assign app groups and wire FSLogix shares without creating subscription-level isolation.
- Dedicated customers: manifests in `onboarding/manifests/dedicated/` are consumed by the dedicated landing zone pipeline which invokes `modules/dedicated` in the target subscription (pipeline config uses manifest.subscription_id to select backend/state and run `tofu -chdir=environments/dedicated apply -var-file=...`).

Operational notes
- Never store secrets in manifests; use secret references or pipeline-managed variables.
- CI should reject manifests that change `environment` without human approval since moving a customer between shared/dedicated has operational impact.
- Add tests under `tests/` for manifest-to-variable conversion logic and for module behavior (`terraform test`).

Examples
- See `onboarding/manifests/shared-example.json` and `onboarding/manifests/dedicated-example.json` in the repo for minimal working examples.
