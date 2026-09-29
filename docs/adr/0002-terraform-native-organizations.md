# ADR 0002: Terraform-Native Organizations vs Control Tower / AFT

- Status: accepted
- Date: 2026-09-29

## Context

Setting up a multi-account AWS landing zone requires automated account vending, Organizational Unit (OU) structure management, and governance guardrails. AWS provides AWS Control Tower and Account Factory for Terraform (AFT), alongside native Terraform `aws_organizations_*` resources.

The organization needs a predictable, fast, and version-controlled mechanism to provision accounts and enforce Service Control Policies (SCPs) and Resource Control Policies (RCPs) without manual console interaction or excessive AWS service costs.

## Decision

Manage the AWS Organization hierarchy, OUs, member accounts, and organization policies using **Terraform-native AWS Organizations resources** (`iac-modules-repo/governance/organization` and `iac-modules-repo/governance/account-factory`).

1. **Declarative OU Tree**: OUs (`Security`, `Infrastructure`, `Workloads`, `Sandbox`, `Policy-Staging`, `Suspended`) are declared in code.
2. **Account Registry as Single Source of Truth**: Accounts are registered in `foundation-live-repo/_config/accounts.hcl` and created by `account-factory`.
3. **No Automatic Account Closing**: AWS APIs do not support deleting accounts cleanly without manual root billing verification; accounts to be decommissioned are moved to the `Suspended` OU where a deny-all SCP isolates them.

## What I chose against and what it cost

- **AWS Control Tower / AFT**:
  - *Why rejected*: Control Tower introduces heavy AWS Service Catalog, Step Functions, and DynamoDB orchestration. Account vending takes 30–45 minutes per account. Customizing guardrails requires navigating AFT pipeline repos, and AWS-managed SCPs frequently collide with custom GitOps IAM boundaries.
  - *Cost of choosing native Terraform*: We must maintain Day-0 bootstrapping, StackSets orchestration, and delegated administrator registrations ourselves.
- **Manual Console Account Creation**:
  - *Why rejected*: Fails infrastructure-as-code principles, leaves account configurations unversioned, and creates configuration drift.

## Consequences

- Complete, instantaneous Terraform plan visibility over organizational structure and policy changes.
- Account creation and placement completes in standard Terraform apply time (< 2 minutes).
- Zero Control Tower overhead or hidden state machines.
