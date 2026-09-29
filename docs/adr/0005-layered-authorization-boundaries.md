# ADR 0005: SCP vs RCP vs Permissions Boundary: Layered Authorization

- Status: accepted
- Date: 2026-09-29

## Context

AWS authorization evaluates multiple policy types when determining whether a principal can execute an API call: Identity-based policies, Resource-based policies, Permissions Boundaries, Service Control Policies (SCPs), and Resource Control Policies (RCPs).

Without a clear architectural division of responsibility, policies become redundant, confusing to debug, or leave critical security gaps.

## Decision

Establish a strict three-tier authorization hierarchy across the platform:

```
[ AWS Request Evaluation Hierarchy ]
1. Organization Guardrail (SCP)          --> Restricts account/OU actions (e.g. Region allow-list, Root deny)
2. Data Perimeter Guardrail (RCP)        --> Restricts resource access to Org principals only (S3, KMS, SQS)
3. Principal Delegation Boundary (IAM PB)--> Restricts maximum permissions newly created roles can have
4. Identity Policy (IAM Role/User)       --> Grants explicit least-privilege allows
```

1. **Service Control Policies (SCPs)**: Guardrails attached at the AWS Organizations OU level.
   - Enforce region allow-lists (`eu-central-1` and `eu-west-1`).
   - Deny root user actions and `LeaveOrganization`.
   - Prevent tampering with platform infrastructure (CloudTrail, Config, GuardDuty, Security Hub, bootstrap roles, state buckets).
   - Require IMDSv2 on EC2 instance launches.
   - Mandate that all IAM role creation must carry `platform-workload-boundary`.
2. **Resource Control Policies (RCPs)**: Data perimeter guardrails attached at the organization level.
   - Enforce `aws:PrincipalOrgID` on S3, KMS, SQS, and Secrets Manager to block access from principals outside the organization regardless of bucket policies.
   - Enforce `aws:SecureTransport` (HTTPS/TLS only).
3. **Permissions Boundaries (`platform-workload-boundary`)**:
   - Attached to all IAM roles created by tenant Terraform or developers.
   - Prevents tenant developers from escalating privileges to `AdministratorAccess` or modifying platform resources.

## What I chose against and what it cost

- **Relying solely on SCPs**:
  - *Why rejected*: SCPs do not restrict resource-policy-based access from outside the account (e.g. a public S3 bucket or cross-account KMS grant). RCPs are necessary to enforce the data perimeter.
- **Relying solely on IAM Policies without Boundaries**:
  - *Why rejected*: If a developer has `iam:CreateRole` and `iam:AttachRolePolicy`, they can grant themselves full administrator privileges. The permissions boundary closes this privilege escalation gap.

## Consequences

- Defense-in-depth: Even if a tenant writes an overly permissive bucket policy or IAM role, the RCP and permissions boundary prevent data exfiltration and privilege escalation.
- Clear debugging guidelines: Organizational denials are separated from identity policy errors.
