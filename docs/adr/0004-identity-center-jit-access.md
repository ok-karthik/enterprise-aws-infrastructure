# ADR 0004: Identity Center + Just-In-Time (JIT) Access vs Standing Admin

- Status: draft
- Date: 2026-09-29

## Context

Managing human operator access to AWS accounts in a scaling enterprise requires balancing operational velocity against the risk of accidental outages and credential theft. Traditional approaches rely on static IAM users with long-lived access keys, or standing `AdministratorAccess` roles attached to engineers' Identity Provider accounts.

Regulatory standards (SOC 2 CC6.1/CC6.3, ISO 27001 A.8.2, BSI C5 IDM) explicitly require multi-factor authentication, least privilege, and strict auditability for privileged actions.

## Decision

Implement centralized **AWS IAM Identity Center** (`iac-modules-repo/identity/identity-center`) in the management account with:
1. **Tiered Permission Sets**:
   - `ReadOnlyAccess` (8h session)
   - `DeveloperAccess` (8h session)
   - `PlatformEngineerAccess` (4h session)
   - `SecurityAuditAccess` (4h session)
   - `BreakGlassAdmin` (1h session)
2. **Zero Standing Admin in Production**: No human holds permanent `AdministratorAccess` in workload production accounts.
3. **Just-In-Time Break-Glass Elevation**: Production emergencies require assuming the `BreakGlassAdmin` permission set, which instantly triggers EventBridge rules and sends high-priority SNS notifications to the security on-call rotation (`security/break-glass-alerts`).

## What I chose against and what it cost

- **Static IAM Users and Access Keys**:
  - *Why rejected*: Statically provisioned keys frequently leak into Git, bash history, or developer laptops. Prohibited by repository SCP `deny_iam_user_creation`.
- **Standing Admin Permissions for Platform Engineers**:
  - *Why rejected*: An engineer with standing admin can bypass change management or accidentally delete production resources.
  - *Cost*: Engineers must request elevated permissions for production troubleshooting, adding minor friction.

## Consequences

- Compliance with SOC 2 CC6.3, ISO 27001 A.8.2, and BSI C5.
- Complete auditability of privilege escalation events in CloudTrail.
- Human users authenticate exclusively through the corporate IdP with MFA enforced.
