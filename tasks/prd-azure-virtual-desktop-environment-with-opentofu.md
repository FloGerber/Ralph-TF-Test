# PRD: Azure Virtual Desktop Environment with OpenTofu

## Overview

This project establishes a complete Azure Virtual Desktop (AVD) infrastructure using OpenTofu following Azure Best Practices, Azure Landing Zone concepts, and the Well-Architected Framework. The environment supports both Shared Hosting (multi-tenant) and Dedicated Hosting (single-tenant) deployment models, with modular and DRY configuration to enable enrollment of multiple customers.

## Goals

- Deploy AVD with Windows 11 multi-session hosts following Azure Reference Architecture
- Implement Hub-and-Spoke network topology with VNet peering
- Create reusable landing zones for Shared and Dedicated hosting
- Automate Golden Image creation using Azure Image Builder
- Configure Entra Domain Services for FSLogix and GPO management
- Provide per-customer Azure Premium Fileshare storage
- Enable multi-customer enrollment in Shared environment
- Support multiple Dedicated Hosting deployments from template

## Quality Gates

These commands must pass for every user story:
- `tofu validate` - OpenTofu validation
- `tofu plan` (no errors) - OpenTofu planning
- `tofu fmt` - Code formatting check
- Azurer CLI validation for networking and resources

For infrastructure stories, also include:
- Verify deployment via Azure Portal or CLI
- Test network connectivity between components

## User Stories

### US-001: Create Hub-and-Spoke Network Foundation
**Description:** As an operator, I want a Hub virtual network with spoke networks for Shared and Dedicated hosting so that AVD workloads are logically separated.

**Acceptance Criteria:**
- [ ] Deploy Hub VNet with Azure Firewall or NVAs
- [ ] Create spoke VNet for Shared Hosting Application landing zone
- [ ] Create spoke VNet for Dedicated Hosting landing zone
- [ ] Configure VNet peering between Hub and spokes
- [ ] Implement network security groups with least-privilege rules

### US-002: Deploy Shared Hosting Application Landing Zone
**Description:** As an operator, I want a modular Shared Hosting landing zone so that multiple customers can be onboarded efficiently.

**Acceptance Criteria:**
- [ ] Create reusable module for Shared Hosting VNet
- [ ] Implement customer isolation using NSGs and RBAC
- [ ] Configure shared AVD host pools with session hosts
- [ ] Set up workspace and application groups
- [ ] Create customer-specific resource groups dynamically

### US-003: Create Dedicated Hosting Landing Zone Template
**Description:** As an operator, I want a reusable Dedicated Hosting landing zone template so that I can deploy isolated environments per customer.

**Acceptance Criteria:**
- [ ] Create modular Terraform/OpenTofu module for Dedicated Hosting
- [ ] Support customer-specific subscription or resource group
- [ ] Implement isolated VNet with private endpoints
- [ ] Configure dedicated AVD host pools
- [ ] Enable parameterization for customer-specific settings

### US-004: Configure Azure Image Builder for Golden Images
**Description:** As an operator, I want automated Golden Image creation using Azure Image Builder so that standardized Windows 11 images are available for AVD hosts.

**Acceptance Criteria:**
- [ ] Set up Azure Image Builder resource and managed identity
- [ ] Create Image Template for Windows 11 multi-session
- [ ] Include custom line-of-business applications in image
- [ ] Configure image replication to target regions
- [ ] Automate image version management

### US-005: Integrate Entra Domain Services
**Description:** As an operator, I want Entra Domain Services configured so that FSLogix profile containers and GPOs work correctly.

****Description:** As an operator, I want Entra Domain Services configured so that FSLogix profile containers and GPOs work correctly.

**Acceptance Criteria:**
- [ ] Deploy Entra Domain Services with managed domain
- [ ] Configure AVD virtual machines to domain join via extension
- [ ] Set up FSLogix profile container storage (Azure Files)
- [ ] Implement GPO settings for AVD users
- [ ] Configure user profile disk (UPD) or FSLogix as fallback

### US-006: Deploy Azure Premium Fileshare per Customer
**Description:** As an operator, I want per-customer Azure Premium Fileshare storage so that each customer has isolated profile and application data.

**Acceptance Criteria:**
- [ ] Create Premium Fileshare for Shared Hosting customers
- [ ] Create dedicated Fileshares per Dedicated Hosting customer
- [ ] Configure private endpoints for storage security
- [ ] Set up role-based access controls per customer
- [ ] Configure NTFS permissions for FSLogix

### US-007: Implement AVD Session Hosts
**Description:** As an operator, I want Windows 11 multi-session hosts deployed and configured so that users can connect to AVD sessions.

**Acceptance Criteria:**
- [ ] Deploy VM scale sets for session hosts
- [ ] Configure Windows 11 Enterprise multi-session OS
- [ ] Join machines to Entra Domain Services
- [ ] Install AVD agent and configure VM extensions
- [ ] Implement load balancing (breadth-first for multi-session)

### US-008: Configure Monitoring with Azure Monitor
**Description:** As an operator, I want comprehensive monitoring so that AVD performance and issues can be tracked.

**Acceptance Criteria:**
- [ ] Set up Log Analytics workspace
- [ ] Configure Azure Monitor for VMs insights
- [ ] Deploy AVD-specific monitoring solutions
- [ ] Create alerting rules for session host health
- [ ] Set up dashboards for AVD monitoring

### US-009: Implement DRY and Modular Configuration
**Description:** As an operator, I want DRY configuration with reusable modules so that the codebase is maintainable and scalable.

**Acceptance Criteria:**
- [ ] Create reusable modules for: networking, AVD, storage, monitoring
- [ ] Use Terragrunt or native OpenTofu for configuration orchestration
- [ ] Implement variables and locals for parameterization
- [ ] Create example configurations for Shared and Dedicated hosting
- [ ] Document module usage and inputs/outputs

### US-010: Set Up Remote State Backend
**Description:** As an operator, I want remote state storage so that team collaboration and state locking work properly.

**Acceptance Criteria:**
- [ ] Create Azure Storage Account for state backend
- [ ] Configure state locking with Blob storage
- [ ] Set up workspaces for different environments
- [ ] Enable encryption at rest
- [ ] Document backend configuration for team

### US-011: Bootstrap Landing Zone Foundation
**Description:** As an operator, I want the base Azure infrastructure bootstrapped so that landing zones can be deployed.

**Acceptance Criteria:**
- [ ] Deploy subscription structure (Management, Connectivity, Shared, Dedicated)
- [ ] Set up Management Groups hierarchy
- [ ] Configure Azure Policy assignments
- [ ] Deploy Log Analytics and Azure Security Center
- [ ] Implement cost management tagging strategy

### US-012: Implement Disaster Recovery
**Description:** As an operator, I want DR capabilities so that AVD services can fail over to secondary region.

**Acceptance Criteria:**
- [ ] Deploy secondary region infrastructure
- [ ] Configure Geo-redundant storage for Fileshares
- [ ] Set up AVD host pools in DR region
- [ ] Document failover procedures
- [ ] Test DR connectivity and access

## Functional Requirements

- FR-1: All resources must follow Azure Well-Architected Framework (Security, Reliability, Performance, Cost, Operations)
- FR-2: Network topology must support Hub-and-Spoke with VNet peering
- FR-3: AVD must use Windows 11 Enterprise multi-session
- FSLogix profile containers must use Azure Premium Fileshare
- Entra Domain Services must provide domain join capability
- Golden Images must be created via Azure Image Builder
- Configuration must be DRY using OpenTofu modules
- State must be stored in Azure Storage Account with locking
- Landing zones must support multi-customer enrollment
- Security must include NSGs, RBAC, and Private Endpoints

## Non-Goals

- On-premises connectivity (ExpressRoute/S2S VPN)
- Third-party monitoring solutions
- Custom image gallery outside of Azure Image Builder
- Legacy Windows 10 deployments
- Manual deployment workflows (full automation required)

## Technical Considerations

- Use Azure Image Builder with managed identity for image creation
- Implement Azure Policy for compliance enforcement
- Use Private Endpoints for all storage and PaaS services
- Configure Network Security Groups with explicit allow rules
- Implement customer isolation in Shared Hosting via RBAC
- Use Azure AD Join for session hosts with Entra ID
- Support both FSLogix and User Profile Disk options
- Leverage Azure Virtual Network integration for App Services if needed

## Success Metrics

- All AVD users can connect to session hosts successfully
- Golden Images are automatically built and available
- Per-customer storage isolation is enforced
- Multi-customer enrollment completes in <1 hour per customer
- DR failover testing succeeds in <30 minutes
- Infrastructure passes Azure Advisor recommendations

## Open Questions

- Should the Shared Hosting use pooled or personal host pools?
- What specific line-of-business applications are needed in the Golden Image?
- Will customers need custom network requirements beyond standard spoke VNet?
- What are the specific retention policies for Log Analytics?
- Should we implement a self-service portal for customer onboarding?