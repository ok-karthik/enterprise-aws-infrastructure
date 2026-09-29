# System Design Walkthrough: Scaling an AWS Foundation from 3 to 50 Teams

This document provides a structured, 20-minute architectural system design narrative. It answers the classic Staff/Principal Infrastructure interview question:
> *"How would you design and evolve an AWS cloud foundation for a high-growth scaleup expanding from 3 engineering teams to 50 teams?"*

---

## Architecture Evolution at a Glance

```
STAGE 1 (Day 1: 3 Teams)
┌──────────────────────────────────────────────┐
│ Single AWS Account (Monolith)               │
│ - Shared VPC (10.0.0.0/16)                   │
│ - 1 EKS Cluster (Namespace isolation)        │
│ - Static IAM Credentials                     │
└──────────────────────────────────────────────┘
       │
       │ Trigger: Blast radius breach, SOC 2 audit, billing disputes
       ▼
STAGE 2 (Scaleup: 10–15 Teams — This Repository's Baseline)
┌───────────────────────────────────────────────────────────────────────────┐
│ AWS Organization (Multi-Account Hub & Spoke)                             │
│ ├── Management (Billing & SCPs only)                                      │
│ ├── Security OU: log-archive (Object Lock) & security-tooling             │
│ ├── Infrastructure OU: network-hub (TGW & Inspection) & shared-services   │
│ └── Workloads OU: workloads-dev & workloads-prod                          │
│                                                                           │
│ - Zero-Key OIDC CI/CD + OPA/Checkov policy gates                          │
│ - SSM Parameter Store Discovery Contract                                  │
│ - IAM Identity Center + JIT Break-Glass Admin                             │
└───────────────────────────────────────────────────────────────────────────┘
       │
       │ Trigger: Platform team ticketing bottleneck, multi-region compliance
       ▼
STAGE 3 (Enterprise: 50+ Teams — Distributed Platform & IDP)
┌───────────────────────────────────────────────────────────────────────────┐
│ Domain-Driven Account Mesh + Internal Developer Platform                 │
│ ├── Domain Workload Accounts: payments-prod, catalog-prod, auth-prod     │
│ ├── Multi-Region Active/Standby: eu-central-1 (Primary) + eu-west-1 (DR)  │
│ ├── Self-Service IDP (Backstage/OpenChoreo) + ACK Cross-Account Vending   │
│ └── Autonomous SRE Healing Agents + Infracost PR Error-Budget Gating      │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Stage 1: The Early-Stage Foundation (3 Teams, 1–2 Accounts)

### The Architecture
- **Account Layout**: A single AWS account, or at most a simplistic `nonprod` vs `prod` split.
- **Networking**: One large monolithic VPC (`10.0.0.0/16`) per account with public/private subnets and local NAT Gateways.
- **Compute**: A single shared Amazon EKS cluster where teams are isolated solely via Kubernetes namespaces and RBAC.
- **Identity & Access**: Engineers use IAM Users with static access keys or shared assumed roles with broad policies.
- **Deployment**: Manual Terraform runs from developer laptops or simple linear GitHub Actions pipelines.

### What Breaks First at Scale
1. **Security & Blast Radius**:
   - Kubernetes namespace isolation does not prevent Linux kernel exploits, cross-namespace network snooping, or IAM instance profile theft.
   - Developers with IAM privileges in dev can accidentally affect production resources or read sensitive state files.
2. **FinOps & Showback**:
   - The monthly AWS bill arrives as a single monolithic invoice. Untangling how much Team Payments spent versus Team Analytics requires heroic tagging compliance that invariably slips.
3. **Network Exhaustion**:
   - Subnet CIDRs run out of private IP addresses as microservices, pods, and databases multiply.

### What to Add Next (Transition to Stage 2)
- Form an AWS Organization.
- Segregate environments into distinct AWS accounts.
- Enforce Day-0 bootstrapping and zero static credentials.
- *Refer to [ADR 0001 (Topology)](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0001-repository-topology.md) and [ADR 0002 (Organizations)](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0002-terraform-native-organizations.md).*

---

## 2. Stage 2: The Multi-Account Hub-and-Spoke Landing Zone (10–15 Teams)

> **This repository represents the production implementation of Stage 2.**

### The Architecture
1. **Organizational Hierarchy (AWS SRA Aligned)**:
   - **Management Account**: Houses Organizations, billing, and IAM Identity Center. Zero workloads run here.
   - **Security OU**:
     - `log-archive`: Centralized S3 buckets with Object Lock in `COMPLIANCE` mode (400-day retention) for CloudTrail, Config, and VPC flow logs ([ADR 0003](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0003-state-architecture-and-day-0.md)).
     - `security-tooling`: Delegated administrator for GuardDuty, Security Hub, Inspector v2, Macie, and AWS Config ([ADR 0002](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0002-terraform-native-organizations.md)).
   - **Infrastructure OU**:
     - `network-hub`: Regional Transit Gateway (TGW) and Central Egress Inspection VPC with AWS Network Firewall ([ADR 0006](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0006-transit-gateway-network-topology.md), [ADR 0007](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0007-central-egress-network-firewall.md)).
     - `shared-services`: Central VPC interface endpoints, private Route 53 zones, and ACK hub controllers.
   - **Workloads OU**:
     - `workloads-dev`, `workloads-staging`, `workloads-prod`: Platform stacks running hardened EKS clusters and databases.
   - **Sandbox & Policy-Staging OUs**: Budget-capped experimentation and safe SCP canary testing.
2. **Layered Authorization & Data Perimeter**:
   - **SCPs**: Regional allow-lists (`eu-central-1` and `eu-west-1`), root access denial, and mandatory permissions boundaries ([ADR 0005](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0005-layered-authorization-boundaries.md)).
   - **RCPs**: Enforce `aws:PrincipalOrgID` across S3, KMS, SQS, and Secrets Manager.
   - **Identity**: IAM Identity Center with Just-In-Time `BreakGlassAdmin` access and automated Slack/SNS alerting ([ADR 0004](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0004-identity-center-jit-access.md)).
3. **Decoupled IaC & Discovery Contract**:
   - Terragrunt separates reusable modules (`iac-modules-repo/`) from live environments ([ADR 0010](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0010-terragrunt-vs-plain-terraform.md)).
   - All tenant-facing metadata is published to SSM Parameter Store (`/platform/${env}/${region}/...`), ensuring tenants never hardcode AWS IDs (`docs/DISCOVERY_CONTRACT.md`).
4. **CI/CD Security Gates**:
   - GitHub Actions assumes narrow OIDC roles directly into target accounts ([ADR 0009](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0009-terraform-orchestrator.md)).
   - Every PR plan is evaluated by TFLint, Checkov, and OPA/Rego policies. Binary plans are verified via SHA256 checksums before apply.

### What Breaks First at 25+ Teams
1. **Platform Team as a Bottleneck**:
   - The central infrastructure team becomes a ticket-taking service desk for vending databases, S3 buckets, and IAM roles.
2. **Terragrunt PR Merge Queues**:
   - Multiple teams submitting infrastructure changes against the shared `workloads-dev` repository trigger state lock contention and serialized CI pipeline runs.
3. **TGW Data Processing Costs & Latency**:
   - High-throughput microservice-to-microservice traffic flowing through the regional Transit Gateway accumulates bandwidth charges ($0.02/GB) and minor latency hops.

### What to Add Next (Transition to Stage 3)
- Introduce an Internal Developer Platform (IDP) for self-service capability vending.
- Transition from shared workload accounts to dedicated domain accounts.
- Implement multi-region disaster recovery and cell-based isolation.

---

## 3. Stage 3: The Enterprise Scale (50+ Teams, Multi-Region)

### The Architecture
1. **Domain-Driven Account Mesh**:
   - Instead of a single shared `workloads-prod` account, vend dedicated accounts per business domain:
     - `payments-prod`, `catalog-prod`, `logistics-prod`, `identity-prod`.
   - **Blast Radius**: An incident or misconfiguration in `catalog-prod` cannot take down payment processing.
   - **FinOps**: Cost allocation is 100% native by account ID in AWS Cost Explorer without complex tagging allocation logic.
2. **Self-Service Developer Platform (IDP)**:
   - Integrate with Backstage / OpenChoreo:
     - Developers select golden-path templates (e.g. "Microservice with PostgreSQL & S3").
     - The template commits tenant manifests to the application repo.
   - **Asynchronous Cloud Vending via ACK / Crossplane**:
     - ACK controllers in the `shared-services` hub cluster assume spoke roles (`identity/ack-cross-account`) to provision RDS, SQS, and S3 inside the tenant's domain account asynchronously without human platform tickets.
3. **Multi-Region Disaster Recovery & Cell Architecture**:
   - **Primary Region**: `eu-central-1` (Frankfurt) — active transaction processing.
   - **Warm Standby Region**: `eu-west-1` (Dublin) — warm standby EKS cluster (node group scale = 0), Aurora Global Database replication, S3 Cross-Region Replication, and Route 53 DNS failover routing (`docs/DISASTER_RECOVERY.md`).
   - RTO target < 15 minutes, RPO target < 1 minute.
4. **Autonomous SRE & AI Agentic Operations**:
   - Automated self-healing CI pipelines (`.agents/scripts/healer_runner.py`) parse execution failures and propose remediations.
   - Nightly drift-detection issues trigger ChatOps `/reconcile` bots to align Terraform state with cloud reality.
   - Agent operations are constrained by strict pre-execution guardrails (`.agents/hooks/guard.py`) and read-only MCP servers ([ADR 0011](file:///Users/karthik.orugonda/github/enterprise-aws-infrastructure/docs/adr/0011-agent-mcp-integration.md)).

---

## 4. Key Architectural Trade-Offs Summary

| Dimension | Stage 1 (3 Teams) | Stage 2 (10–15 Teams — Current) | Stage 3 (50+ Teams — Future) |
|---|---|---|---|
| **Account Strategy** | 1–2 Monolithic Accounts | 8–10 Core Function & Tier Accounts | 50+ Domain-Oriented Accounts |
| **Network Topology** | Single Flat VPC | Regional Transit Gateway + Central Inspection | TGW + VPC Lattice / PrivateLink Mesh |
| **Egress Strategy** | Local NAT Gateways per Subnet | Central Egress + Network Firewall | Distributed VPC Endpoints + Central Firewall |
| **Provisioning Model** | Manual PRs / CLI applies | Centralized GitOps CI/CD (Terragrunt) | Self-Service IDP + ACK Hub-and-Spoke |
| **Disaster Recovery** | Single-Region Backups | Warm Standby Multi-Region (Frankfurt/Dublin) | Multi-Region Active-Active Cell Routing |
| **FinOps Visibility** | Single Consolidated Invoice | OU Cost Anomaly Detection + Budgets | 100% Direct Account Showback |
| **Security Gates** | Code Review only | Blocking Checkov, OPA, TFLint in CI | Shift-Left Developer CLI + Runtime Auto-Remediation |
