Testing Strategy
================

This document defines the repository-level testing strategy required by US-015. It is intentionally practical and CI-first: tests must be runnable in a controlled CI runner and fast where possible.

1) Test Goals
- Validate module behaviour (resource types, counts, optional features).
- Validate onboarding manifests and variable contracts used to drive deployments.
- Provide environment-level verification guidance for integration tests and manual acceptance.

2) Tooling and equivalence
- OpenTofu (`tofu`) is the canonical tool used in CI for formatting, validation and test execution. Use `tofu` where possible; treat `tofu test` as the OpenTofu equivalent of `terraform test`.
- Static security scans use `checkov -d .`.

3) Test types and responsibilities
- Unit / Module tests (author responsibility):
  - Location: `modules/<module>/tests/*.tftest.hcl`.
  - Use OpenTofu `mock_provider` to avoid provisioning cloud resources.
  - Focus: resource shapes, conditional rendering, variable defaults, and outputs.
  - Execution: `tofu test` against the module directory.

- Environment / Integration tests (platform/QA responsibility):
  - Location: `environments/*/tests/` or a dedicated `tests/integration/` folder.
  - Execution: `tofu test` with real providers (requires credentials), run in a gated CI runner or ephemeral test subscription.
  - Focus: end-to-end variable wiring, manifest consumption, backend integration, and cross-module outputs (for example: hostpool → session host registration → FSLogix storage mount validation where feasible).

- Manifest & schema validation (CI responsibility):
  - Validate onboarding manifests using the repository JSON Schema (`onboarding/schema/onboarding.schema.json`) in CI (example: `ajv`, `jq` or a small Node/Go validator). Failing manifest validation must block further pipeline stages.

4) Shared vs Dedicated test scope
- Shared landing zone (fast path):
  - Module unit tests: `modules/avd`, `modules/networking`, `modules/storage`, `modules/fslogix`, etc. must have `.tftest.hcl` unit tests.
  - Integration tests: smoke `tofu test` runs in a test subscription validating workspace + host pool + a minimal session host registration (ephemeral).

- Dedicated landing zone (isolation path):
  - Module unit tests: `modules/dedicated` must have unit tests that validate composition (peering, storage wiring, host pool outputs).
  - Integration tests: full stack tests run only in a gated CI job with appropriate subscription-level credentials and budget/time limits.

5) Test expectations (manifests, variables, outputs)
- Manifests: CI validates manifests against JSON Schema; templates must fail fast on missing required fields.
- Variable contracts: modules must declare sensible defaults, and tests must assert behavior for default vs explicit values. Tests should assert presence and shape of critical outputs (IDs, connection strings, storage endpoint URLs).
- Module outputs: tests must assert outputs are non-empty and parsable (for example: `output.host_pool_ids` contains at least one id when host pools are configured).

6) CI/CD gating (recommended pipeline jobs)
- format-check: `tofu fmt -check` (fail fast)
- validate: `tofu validate` (fail fast)
- module-tests: run `tofu test` against discovered `modules/*/tests/*.tftest.hcl` using mock providers (unit tests) — blocking for PRs
- security-scan: `checkov -d .` (blocking or advisory depending on policy severity)
- integration-tests: gated job that runs longer `tofu test` runs in a controlled test subscription; only run after policy and unit-test jobs pass and behind approval for costful tests

7) Operational notes and gotchas
- Mock provider tests require OpenTofu >= 1.7 (mock_provider support).
- Local developer machines may lack `tofu`/OpenTofu, `terraform`, or `checkov` — CI runners must provide the tooling.
- Tests that create long-lived resources must be gated and cleaned up; prefer lightweight, fast smoke tests in PR gates.

8) Required checks for PRs (per US-015 acceptance)
- `tofu fmt -check` passes
- `tofu validate` passes
- `tofu test` (module/unit) passes
- `checkov -d .` passes

9) Example CI snippet (discovery)
The CI selector job should discover module unit tests and run them with mock providers:

  TEST_DIRS=$(git ls-files "**/tests/*.tftest.hcl" | sed 's#/[^/]*$##' | sort -u)
  for d in $TEST_DIRS; do (cd "$d" && tofu test -no-color); done

10) Next actions
- Ensure every module under `modules/` has at least one focused `.tftest.hcl` (existing: `networking`, `avd`, `storage`, `dedicated`).
- Add environment-level `tests/` folders for any long-running integration suites and wire them into the gated CI job.

References
- PRD tasks and CI/CD patterns are documented in `.github/workflows/ci-cd.yml`, `tasks/prd.json` and `.ralph-tui/progress.md`.
