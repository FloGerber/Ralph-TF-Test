AVD Day-N Operations and Scaling

Purpose
- Define automated controls for capacity (scaling plans) and operational Day-N tasks so platform operators can manage lifecycle without manual, ad-hoc intervention.

Scope
- Applies to both shared and dedicated AVD landing zones implemented in this repo. Leverages existing patterns: `imaging/image-builder`, `modules/avd`, and `docs/app-attach.md`.

1) AVD Scaling Plans (Architecture)
- Represent scaling plans as declarative artifacts stored in Git. A `scaling_plans/` manifest directory contains one YAML/JSON per plan describing schedule, metrics, min/max/session-host counts, and host-pool targets. CI converts promoted manifests into Terraform variable updates (`scaling_plan_id` / module inputs) or directly applies via `modules/avd` `azurerm_scaling_plan` resource blocks.
- The platform exposes compact inputs from modules (`avd_scaling_plan_id`, `avd_image_id`) so promotion is a single variable/module update in environment stacks.
- For autoscaling based on metrics, use Azure Monitor autoscale rules where available or hostpool scheduled scaling for predictable workloads. Store recommended defaults in `environments/shared/locals.tf` so tenants inherit safe floors/ceilings.

2) Day-N Operations (image refresh, host replacement/update, App Attach updates)
- Image refresh: Image Builder publishes SIG versions; imaging CI triggers builds and, when promoted, updates `avd_image_id` in environment variables. A promotion PR triggers `tofu validate` and `terraform test` in CI then applies the image change. Hosts roll using a controlled update strategy (drain sessions → deallocate/replace VMs or upgrade VMSS instances → rejoin hostpool).
- Host replacement/update: Implement a rolling host replacement process: 1) identify candidate hosts (via VMSS instance health or hostpool status), 2) drain existing sessions (PowerShell Az/WMI or AVD management APIs), 3) deallocate and reprovision from SIG image or upgrade VMSS model, 4) rejoin to hostpool and verify service probes. Automate using an Azure Function / pipeline job that can be executed from CI and driven by a PR for safety.
- App Attach updates: Follow the App Attach packaging & release pattern documented in `docs/app-attach.md`. CI publishes package versions to staging share, validates on a test hostpool, and promotion copies to production share and updates a manifest file (tracked in Git). Terraform picks up the updated manifest path and updates `appattach_manifest_path` in the environment to point at the new version.

3) Drift Detection and Remediation (GitOps-oriented model)
- Detection: Periodically run drift scans in CI (or scheduled platform job) using `terraform plan`/`tofu plan` against deployed state and `az cli` / resource graph queries for out-of-band changes. Store findings in a repository issue or an alerts channel with a machine-readable report (JSON) attached.
- Workflow: For actionable drift, the system generates a change branch with a proposed fix: the platform autorun creates a branch `autofix/drift/<resource>-<ts>` with TF changes (or module variable reconcile) and opens a PR that includes: (1) automated plan output, (2) impact summary, and (3) remediation test steps. Operators review, merge, and CI applies.
- Remediation policy: By default, remediation is PR-gated. For trivial, low-risk fixes (tagging, diagnostic setting reassertion), consider an automated merge policy backed by an exception list and strict audit logging.

4) Single-region production resilience & DR rebuild/runbook
- Assumptions: Single-region production has high-availability within the region but is NOT resilient to full-region failure. Design for rapid rebuild (RTO measured in hours) rather than synchronous multi-region availability.
- Required artifacts for DR: 1) Infrastructure-as-Code (this repo) with environment variables/secret wiring, 2) bootstrapped remote backend guidance (`bootstrap` outputs), 3) exported inventory: hostpool names, workspace IDs, storage shares, App Attach manifests, SIG image ids, and Key Vault secret names, 4) a documented runbook to rebuild core platform resources and rehydrate landing zones.
- Runbook highlights: restore remote backend config, run `tofu init` with backend, apply `bootstrap/` to recreate policies and Log Analytics, restore storage and Key Vault secrets (SAS or Key Restore), promote imaging artifacts or re-run Image Builder, apply landing zone stacks, restore App Attach packages to production shares, validate hostpools and assign workspaces. Include a timeline, prioritized steps, and verified smoke tests.

5) Zone-aware deployment guidance
- Where upstream Azure resources support availability zones (VMSS, storage ZRS, disk placement), prefer zone-aware placement for session hosts and supporting storage endpoints. Document zone-aware inputs in `modules/avd` so environments can pass `zones = [1,2,3]` when subscription/region supports it. For platform services that lack zones (some PaaS endpoints), rely on regional redundancy and prepare DR runbook steps.

6) Observability & Testing
- Ensure telemetry for capacity and lifecycle operations is emitted to the central Log Analytics workspace: scaling events, image promotions, host replacement jobs, and drift scan results.
- Add automated acceptance tests to `test/` that validate scaling plan creation and image promotion flows (these tests should be runnable by CI and referenced by `terraform test`).

7) Security & Compliance
- All automation uses OIDC workload identities and follows the repository delivery guidance in `BACKEND.md`. Promotion and remediation PRs must include audit metadata (actor, trigger, pipeline run id).

References
- imaging/image-builder/ (image pipeline)
- docs/app-attach.md (App Attach packaging & release)
- modules/avd/ (scaling plan inputs and hostpool composition)
