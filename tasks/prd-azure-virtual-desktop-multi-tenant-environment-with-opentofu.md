# PRD: Azure Virtual Desktop Multi-Tenant Environment with OpenTofu

## Overview
Build a production-grade Azure Virtual Desktop (AVD) environment supporting both shared multi-tenant hosting and dedicated single-tenant deployments. The solution must follow Azure Landing Zone best practices, align with the Well-Architected Framework, and be fully automated using OpenTofu with modular, DRY configurations. The environment will serve multiple customers with a custom Line of Business application, providing optional isolation through dedicated AVD environments while maintaining consistent security, compliance, and governance.

## Goals
- Deploy a scalable, secure AVD infrastructure aligned with Azure Landing Zone architecture
- Enable both shared and dedicated hosting models with proper IAM and security isolation
- Automate the entire infrastructure provisioning using OpenTofu with reusable modules
- Implement Azure best practices including Hub-and-Spoke networking, Entra Domain Services, and FSLogix
- Provide golden image management through Azure Image Builder
- Ensure all configurations pass quality gates (formatting, validation, security scanning with Checkov)
- Support per-customer Azure Premium File Shares for data isolation
- Enable environment bootstrapping for rapid deployment
- Maintain DRY, modular code aligned with OpenTofu best practices

## Quality Gates

These commands must pass for every user story:
- `tofu fmt -check` - OpenTofu format validation
- `tofu validate` - OpenTofu configuration validation
- `checkov -f <file> --framework opentofu` - Security and misconfiguration scanning

For infrastructure provisioning stories, also verify:
- Successful Checkov scan with no critical/high findings (or documented exceptions)
- Alignment with Azure Well-Architected Framework pillars

## User Stories

### US-001: Design Azure Landing Zone structure with Hub-and-Spoke networking
**Description:** As an infrastructure architect, I want a properly segmented Azure landing zone with Hub-and-Spoke networking so that shared services are centralized and workloads are isolated by spoke.

**Acceptance Criteria:**
- [ ] Hub VNet created with core services (Bastion, NAT Gateway, ExpressRoute gateway)
- [ ] Shared spoke VNet for Application Landing Zone
- [ ] Dedicated spoke VNet template created for customer-specific spokes
- [ ] Hub-to-spoke peering configured with proper routing
- [ ] Network security groups (NSGs) define traffic rules per spoke
- [ ] Documentation describes network topology and isolation boundaries
- [ ] Configuration passes `tofu fmt -check`, `tofu validate`, and Checkov scan

### US-002: Create shared Application Landing Zone for multi-tenant hosting
**Description:** As a platform operator, I want a dedicated Application Landing Zone spoke for the shared AVD environment so that all customers can be hosted efficiently while maintaining logical separation.

**Acceptance Criteria:**
- [ ] Spoke VNet created in landing zone (separate from hub)
- [ ] Subnet structure: AVD hosts, FSLogix storage, application resources
- [ ] Network policies and NSGs configured for AVD requirements
- [ ] Integration with hub services (DNS, Bastion, firewalls)
- [ ] Resource group structure aligned with Azure best practices
- [ ] Terraform outputs expose VNet/subnet IDs for downstream modules
- [ ] Configuration passes all quality gates

### US-003: Design reusable "Dedicated Customer" hosting module
**Description:** As a platform engineer, I want a parameterized Terraform module for dedicated customer environments so that each customer can quickly get their own isolated AVD setup.

**Acceptance Criteria:**
- [ ] Module accepts customer name, user count, and AVD image as inputs
- [ ] Module creates customer-specific spoke VNet with proper isolation
- [ ] Module creates customer resource group following naming conventions
- [ ] Module creates storage account with Premium File Share per customer
- [ ] Module creates single AVD host pool with 1 host, auto-scaling to 2-4 hosts
- [ ] Module configures Entra Domain Services integration
- [ ] Module uses shared golden image from central image builder
- [ ] Module outputs workspace ID, host pool ID, and storage endpoints
- [ ] Module is fully reusable across different customers
- [ ] Configuration passes all quality gates

### US-004: Implement shared hosting AVD configuration
**Description:** As a platform operator, I want the shared AVD environment configured so that multiple customers can access the LOB application simultaneously with per-customer data isolation.

**Acceptance Criteria:**
- [ ] Single AVD host pool created in shared Application Landing Zone spoke
- [ ] Windows 11 multisession session hosts deployed
- [ ] Host pool configured with app groups for the LOB application
- [ ] Workspace created linking to host pool and app groups
- [ ] Load balancing algorithm configured (breadth-first)
- [ ] Scaling plan configured for business hours auto-scaling
- [ ] Host pool supports 1-5 concurrent users initially, scalable
- [ ] Configuration passes all quality gates

### US-005: Set up Entra Domain Services and FSLogix configuration
**Description:** As a security architect, I want Entra Domain Services integrated with FSLogix so that user profiles and group policies are centrally managed across all environments.

**Acceptance Criteria:**
- [ ] Azure AD Domain Services (Entra Domain Services) deployed
- [ ] AADDS domain created and configured
- [ ] Hybrid identity synchronization enabled from on-premises if applicable
- [ ] FSLogix configuration captures user profiles to shared file shares
- [ ] FSLogix rule sets configured per customer/environment
- [ ] Group Policy Objects (GPOs) define security baselines for session hosts
- [ ] AADDS integrated with both shared and dedicated AVD environments
- [ ] Configuration passes all quality gates and security scanning

### US-006: Create golden image with Azure Image Builder
**Description:** As a platform engineer, I want a golden image built automatically so that all AVD session hosts use consistent, hardened Windows 11 multisession configurations.

**Acceptance Criteria:**
- [ ] Image Builder template created for Windows 11 multisession
- [ ] Image includes LOB application and all required dependencies
- [ ] Security hardening applied (Windows Defender, firewall rules)
- [ ] FSLogix agent installed and configured
- [ ] Entra client installed for domain join
- [ ] Image Builder pipeline triggers on configuration changes
- [ ] Image versioned and accessible via Shared Image Gallery (SIG)
- [ ] Configuration passes all quality gates

### US-007: Configure Azure Premium File Shares for customer data isolation
**Description:** As a platform architect, I want per-customer Azure Premium File Shares so that each customer's data is isolated and performance is guaranteed.

**Acceptance Criteria:**
- [ ] One storage account per customer created
- [ ] Premium tier file shares provisioned (100GB minimum, scalable)
- [ ] SMB security configured (encryption, authentication)
- [ ] RBAC roles assigned to customer identities for access
- [ ] Backup configured for disaster recovery
- [ ] Shared Application Landing Zone has dedicated Premium File Share for App Attach
- [ ] File share endpoints exposed via outputs for mounting in AVD
- [ ] Configuration passes all quality gates

### US-008: Configure App Attach with centralized application delivery
**Description:** As a platform operator, I want App Attach configured so that the LOB application is centrally stored and mounted dynamically to reduce image size and enable rapid application updates.

**Acceptance Criteria:**
- [ ] Dedicated Premium File Share created in hub or shared spoke for App Attach
- [ ] App Attach images properly staged on file share
- [ ] App Attach configured in AVD host pool
- [ ] Application dynamically mounts for users at session start
- [ ] Application updates don't require session host image updates
- [ ] Shared and dedicated environments both support App Attach
- [ ] Configuration passes all quality gates

### US-009: Implement IAM and RBAC for multi-tenant security
**Description:** As a security architect, I want fine-grained IAM and RBAC configured so that customers can only access their own resources and data.

**Acceptance Criteria:**
- [ ] AVD built-in roles (Virtual Machine User Login, Desktop Virtualization User) assigned per customer
- [ ] Storage account contributor roles assigned per customer to their file shares only
- [ ] Resource group-level RBAC restricts customer access to their resources
- [ ] Service principal or managed identity created for automation
- [ ] Entra groups created per customer for streamlined access management
- [ ] Audit logging enabled for all role assignments
- [ ] Documentation defines role hierarchy and access boundaries
- [ ] Configuration passes all quality gates and security scanning

### US-010: Set up infrastructure bootstrapping
**Description:** As a platform operator, I want to bootstrap the entire environment with a single command so that new customers or environments can be deployed rapidly.

**Acceptance Criteria:**
- [ ] Bootstrap script created to initialize Azure subscription/resource group
- [ ] Script provisions landing zone prerequisites (hub, shared spoke, AADDS)
- [ ] Script generates Terraform backend configuration
- [ ] Script creates initial golden image
- [ ] Script provisions shared AVD host pool and resources
- [ ] Bootstrap script idempotent and safe to re-run
- [ ] Clear documentation on bootstrap prerequisites and parameters
- [ ] Configuration passes all quality gates

### US-011: Organize Terraform code as modular, DRY modules
**Description:** As a platform engineer, I want code organized into reusable modules so that configurations are maintainable, testable, and follow OpenTofu best practices.

**Acceptance Criteria:**
- [ ] Module structure created: `./modules/networking`, `./modules/avd`, `./modules/storage`, `./modules/image-builder`, `./modules/entra-ds`, `./modules/iam`
- [ ] Shared hosting module created: `./modules/avd-shared`
- [ ] Reusable dedicated hosting module created: `./modules/avd-dedicated`
- [ ] Each module has clear inputs, outputs, and variables
- [ ] No code duplication across modules
- [ ] Shared sub-modules used by both dedicated and shared modules
- [ ] Root module composition uses variables to select shared vs. dedicated
- [ ] Module documentation includes variable descriptions and usage examples
- [ ] All modules pass `tofu fmt -check`, `tofu validate`, and Checkov
- [ ] Root module includes appropriate variable files (terraform.tfvars)

### US-012: Integrate Azure Verified Modules (AVM) where applicable
**Description:** As a platform engineer, I want to use Azure Verified Modules where available so that we leverage Microsoft-supported, well-tested patterns.

**Acceptance Criteria:**
- [ ] Identify AVMs applicable to the architecture (networking, VMs, storage, etc.)
- [ ] Integrate AVMs for VNet, subnet, storage account, and VM deployment where appropriate
- [ ] Document which AVMs are used and why
- [ ] Module wrapping done if AVM defaults need customization
- [ ] All integrated modules are sourced from official Microsoft AVM registry
- [ ] Configuration passes all quality gates

### US-013: Configure security scanning with Checkov
**Description:** As a security engineer, I want automated Checkov scanning so that configurations are validated against security best practices before deployment.

**Acceptance Criteria:**
- [ ] Checkov framework configured for OpenTofu (`--framework opentofu`)
- [ ] Custom policies created for organization-specific rules if needed
- [ ] Checkov integrated into CI/CD pipeline (if applicable)
- [ ] Critical and high-severity findings documented with remediation plans
- [ ] Checkov results exported in reportable format (JSON)
- [ ] Documentation explains which checks apply and any documented exceptions
- [ ] All configurations pass Checkov scan prior to deployment
- [ ] Configuration passes all quality gates

### US-014: Create documentation and operational runbooks
**Description:** As an operations team, I want comprehensive documentation so that the environment can be deployed, maintained, and troubleshot effectively.

**Acceptance Criteria:**
- [ ] README.md created with architecture overview and prerequisites
- [ ] Deployment guide with step-by-step instructions
- [ ] Variable documentation (what each variable does, valid values)
- [ ] Architecture diagram (VNet topology, resource layout, IAM model)
- [ ] Runbook for adding a new dedicated customer
- [ ] Runbook for scaling shared environment
- [ ] Troubleshooting guide for common issues
- [ ] Security and compliance documentation
- [ ] Backup and disaster recovery procedures documented
- [ ] All documentation is clear and operationally focused

### US-015: Implement monitoring and logging
**Description:** As an operations team, I want comprehensive monitoring and logging so that issues can be detected and debugged efficiently.

**Acceptance Criteria:**
- [ ] Log Analytics workspace created
- [ ] AVD diagnostic settings configured (session host logs, app group logs)
- [ ] Storage account diagnostic settings enabled
- [ ] Entra Domain Services logging configured
- [ ] Alerts configured for critical events (session host failures, quota limits)
- [ ] Cost analysis configured to track spending per customer (shared vs. dedicated)
- [ ] Backup monitoring configured for file shares
- [ ] Configuration passes all quality gates

### US-016: Configure cost governance and budgets
**Description:** As a platform architect, I want cost governance configured so that spending is tracked, budgeted, and anomalies are detected.

**Acceptance Criteria:**
- [ ] Azure Budgets created per customer (shared and dedicated)
- [ ] Cost anomaly detection configured
- [ ] Budget alerts configured to notify when thresholds are approached
- [ ] Tagging strategy implemented (customer, environment, cost center)
- [ ] Cost allocation enabled for chargeback if needed
- [ ] Monthly cost reporting configured
- [ ] Configuration passes all quality gates

## Functional Requirements

- **FR-1:** The system must provision a complete Azure Landing Zone with Hub-and-Spoke networking aligned with Azure best practices
- **FR-2:** The shared AVD environment must support simultaneous multi-customer access with per-customer data isolation
- **FR-3:** The dedicated AVD module must create isolated single-customer environments with 1 host scaling to 2-4 hosts based on demand
- **FR-4:** All session hosts must be Windows 11 multisession with the golden image built by Azure Image Builder
- **FR-5:** FSLogix must be configured to store user profiles in per-customer Azure Premium File Shares
- **FR-6:** Entra Domain Services must be integrated for centralized identity and group policy management
- **FR-7:** All resources must be deployed and managed via OpenTofu with no manual provisioning
- **FR-8:** All infrastructure code must pass `tofu fmt -check`, `tofu validate`, and Checkov security scanning
- **FR-9:** The environment must support bootstrapping via a single initialization script
- **FR-10:** RBAC and IAM must enforce complete isolation between customers (shared environment) and complete isolation for dedicated environments
- **FR-11:** App Attach must be configured for centralized LOB application delivery
- **FR-12:** Azure Premium File Shares must be provisioned one per customer with SMB encryption and RBAC
- **FR-13:** The infrastructure code must be modular, DRY, and follow OpenTofu/Terraform best practices
- **FR-14:** Azure Verified Modules must be used wherever applicable
- **FR-15:** Comprehensive monitoring, logging, and cost governance must be implemented and tracked per customer

## Non-Goals (Out of Scope)

- Custom AVD scaling logic beyond built-in Azure scaling plans (advanced ML-based predictions)
- Migration of existing AVD environments (greenfield only)
- Desktop image customization per customer (all share golden image, App Attach enables app variation)
- On-premises connectivity setup (Hub can support ExpressRoute, but connection not configured)
- Third-party identity provider integration (Entra/AAD only)
- Custom Terraform provider development (use existing providers only)
- Performance testing and capacity planning (baseline only)
- Application development or LOB application infrastructure beyond AVD hosting
- Compliance certifications (FedRAMP, HIPAA, etc.) - framework only, not achieved

## Technical Considerations

- **Entra Domain Services latency:** AADDS deployment takes 30+ minutes; plan accordingly in bootstrap script
- **Golden image versioning:** Image Builder creates versioned images in Shared Image Gallery; drift detection recommended
- **FSLogix profile storage:** Premium file shares ensure performance; monitor profile disk usage to prevent quota issues
- **Azure Verified Modules versions:** Pin AVM versions in module registries to prevent unexpected updates
- **Checkov false positives:** Some checks may need documented exceptions; maintain a exceptions policy
- **Regional dependencies:** Ensure all resources deployed to same region for latency and compliance
- **Hybrid identity (if applicable):** If synchronizing users from on-premises AD, Azure AD Connect or Azure AD Connect Cloud Sync must be configured separately
- **Network bandwidth:** Premium file shares and App Attach can consume significant egress bandwidth; monitor costs
- **DNS resolution:** Ensure session hosts can resolve Entra Domain Services DNS; configure conditional forwarders if needed
- **Backup retention:** Premium file shares should have backup retention aligned with RPO/RTO requirements
- **Cost estimation:** Run cost calculator for different user load scenarios (shared vs. dedicated mix) before deployment

## Success Metrics

- All infrastructure provisions successfully without manual intervention on initial deployment
- All Terraform code passes `tofu fmt -check`, `tofu validate`, and Checkov with 0 critical/high findings
- Users can successfully log into shared AVD environment and access LOB application
- Users can successfully log into dedicated customer environments with complete isolation
- Per-customer file shares accessible to authorized users only
- Session host scaling performs as expected based on load
- Golden image updates deploy to new session hosts without manual intervention
- Checkov scans run in <5 minutes per configuration file
- Documentation enables new operator to deploy environment without expert assistance
- Cost reports accurately track spending per customer

## Open Questions

- **On-premises integration:** Will this environment require hybrid identity integration with on-premises AD? If so, Azure AD Connect or Cloud Sync must be configured separately.
- **Regional resilience:** Should the landing zone support multi-region failover? Current design assumes single region.
- **Custom Entra DS configuration:** Are there specific group policies or custom configurations required for the LOB application?
- **App Attach versioning:** How will application versions be managed and staged? Manual or automated pipeline?
- **Disaster recovery RTO/RPO:** What are the recovery time and recovery point objectives for this environment?
- **Compliance/audit requirements:** Are there specific compliance requirements (SOC2, ISO 27001, etc.) that should inform policy configurations?
- **Image update frequency:** How often will the golden image be updated? Weekly? Monthly? Quarterly?
- **Dedicated environment parameters:** Besides customer name and user count, are there other parameters that should be customizable per dedicated environment?