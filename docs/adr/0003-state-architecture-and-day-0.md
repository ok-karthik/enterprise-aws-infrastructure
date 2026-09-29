# ADR 0003: State Bucket Per Account vs Central State Account & Day-0 in CloudFormation StackSets

- Status: accepted
- Date: 2026-09-29

## Context

Terraform and Terragrunt require an S3 backend to store state files and manage state locks. In a multi-account organization, state files can either be centralized into a dedicated "state/shared services" account or distributed into each individual member account. Furthermore, a mechanism is required to provision the state bucket, IAM OIDC trust, and GitHub Actions CI roles in member accounts before any Terraform code can run.

## Decision

1. **State Bucket per Account**: Each member account owns its own S3 state bucket (`tg-state-<account-id>`) with S3 Object Lock, AES256 server-side encryption, and versioning enabled. S3 native state locking (`use_lockfile = true`) is used, eliminating DynamoDB state locking tables.
2. **Day-0 Bootstrap via CloudFormation StackSets**: The management account runs `foundation-live-repo/_bootstrap/bootstrap.sh` once to create the bootstrap template. Service-managed CloudFormation StackSets (`governance/bootstrap-stacksets`) automatically deploy `account-bootstrap.yaml` to all member accounts across targeted OUs.

## What I chose against and what it cost

- **Centralized State Bucket in a Shared Services Account**:
  - *Why rejected*: Storing all account states in a single bucket concentrates blast radius: a compromised credential in the state account compromises the infrastructure secrets of every account in the company. Network partitions or IAM permission errors in the central account halt CI/CD org-wide.
  - *Cost*: A Day-0 bootstrap stack must exist in every member account before Terragrunt can plan or apply.
- **Using Terraform/Terragrunt for Day-0**:
  - *Why rejected*: Chicken-and-egg dilemma. Terragrunt cannot run without an existing S3 state bucket. Passing `--backend-bootstrap` risks unmanaged bucket drift and violates deterministic state key policies.
  - *Cost*: Maintaining one CloudFormation template (`cloudformation/account-bootstrap.yaml`) and validating it with `cfn-lint`.

## Consequences

- Absolute isolation of state blast radius between environments: dev compromise cannot reach production state files.
- Zero DynamoDB cost or provisioning overhead.
- Member account onboarding is fully automated when placed in an OU via StackSets.
