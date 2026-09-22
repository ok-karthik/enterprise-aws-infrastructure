# 🏛️ Platform Governance & Compliance

This document outlines the operational guardrails and compliance standards enforced across the Enterprise AWS Platform.

## 🏷️ Tagging Policy
Mandatory tags are enforced at the Plan JSON level via OPA (Open Policy Agent). Any resource missing these tags will fail the CI/CD pipeline.

| Tag | Required | Purpose |
| :--- | :--- | :--- |
| `Environment` | Yes | Cost allocation and environment isolation (Dev/Prod) |
| `Project` | Yes | Project grouping for unified billing |
| `Service` | Yes | Identifies the specific functional component |
| `Owner` | Yes | Team that owns the resource (from `account.hcl`) |
| `DataClassification` | Yes | `public` / `internal` / `confidential` (from `account.hcl`) |
| `ManagedBy` | Yes | Set to `Terragrunt` to identify IaC resources |
| `CostCenter` | Optional | Internal department billing |

## 🛡️ Security Architecture

### Identity & Access (IAM)
- **Zero-Key Pipeline**: No AWS IAM Users or static Access Keys are used. All CI/CD deployments use short-lived **OIDC tokens** via GitHub Actions.
- **Least Privilege**: CI uses a read-only `github-actions-plan` role (PRs, `main`, drift) and a separate `github-actions-apply` role that only the `dev` / `prod` GitHub Environments can assume, capped by a permissions boundary. Humans get `PlatformEngineer` (power user, IAM limited to `role/platform/*`); `BreakGlassAdmin` (1-hour sessions) exists but is not assigned to anyone by default.
- **Account guard**: stacks refuse to run against any account other than the one in `account.hcl`.

### Encryption
- **At Rest**: KMS encryption is mandatory for all S3 buckets, RDS instances, and EBS volumes.
- **In Transit**: TLS 1.2+ is enforced for all API endpoints; the data-perimeter RCPs (below) deny any request over plain HTTP for the services they cover.

### Organization guardrails (PLAN 4.6)
- **SCPs** (`governance/organization`): deny root user actions, leaving the organization, disabling CloudTrail/Config/GuardDuty/Security Hub/Access Analyzer/Macie, creating IAM users or access keys (except break-glass), and creating an IAM role without the `platform-workload-boundary`; protect `platform-*`/`github-actions-*` roles, the GitHub OIDC provider and `tg-state-*` buckets (except StackSets and break-glass); require IMDSv2; one region allow-list SCP per OU. Sandbox gets its own opt-in guardrails (large instances, RI/Savings Plan purchases); Suspended gets a deny-all. **Every one of these defaults to Policy-Staging only** (or, for Sandbox/Suspended, to that OU alone): nothing widens without a deliberate change — test on throw-away accounts first.
- **RCPs** (`governance/data-perimeter`): deny S3/KMS/SQS/Secrets Manager access from outside the organization, and require TLS. `sts` is a supported but not default-enabled service (see the module README before turning it on: it also covers the actions that create the org's first session).

### Detection and response (PLAN 4.1, 4.2, 4.4, 4.5, 4.9)
- **Log archive** (`security/log-archive`): Object Lock (COMPLIANCE, 400 days for CloudTrail/Config) S3 buckets in the `log-archive` account for every audit log type.
- **Organization CloudTrail** (`security/org-cloudtrail`): one multi-region trail covering every account, delivering to the log archive plus its own CloudWatch Logs group.
- **GuardDuty, Security Hub, Inspector v2, Macie** (`security/threat-detection`): auto-enabled organization-wide from `security-tooling`, the delegated administrator.
- **Alerting** (`security/security-alerts`): EventBridge rules for GuardDuty/Security Hub findings, root sign-in and Organizations policy changes, each an encrypted SNS topic with email subscriptions.
- **Auto-remediation** (`security/auto-remediation`): a Lambda removes an open `0.0.0.0/0`/`::/0` SSH/RDP security group rule within seconds of it being created (target < 30s, measured in `docs/runbooks/auto-remediation.md`).

## 🚦 Change Management (GitHub)

### 🛡️ Recommended GitHub Branch Protection Rules
To ensure the integrity of the `main` branch, the following **GitHub UI settings** (Settings → Branches → Add rule) should be configured:

1.  **Branch name pattern**: `main`
2.  **Require a pull request before merging**: Checked.
    - **Require approvals**: 1
3.  **Require status checks to pass before merging**: Checked.
    - **Status checks**:
        - `🔍 Static Analysis (TFLint/Checkov)`
        - For each account that runs in CI (the matrix in `docs/CICD.md`), for example `workloads-dev`: `workloads-dev / 📝 Plan: workloads-dev`, `workloads-dev / ⚖️ Security & Governance (OPA/Checkov): workloads-dev` and `workloads-dev / 💰 Cost Analysis (Infracost): workloads-dev`. Add the same three for `workloads-prod` and every other account once it has a real id.
4.  **Require conversation resolution before merging**: Checked (ensures all reviewer comments are addressed).
5.  **Restrict deletions**: Checked.

### Blast Radius Mitigation
- **Environment Isolation**: Dev and Prod environments live in separate VPCs (and ideally separate AWS accounts).
- **Parallel Validation**: All modules are planned and validated in parallel to catch cross-module dependencies early.

## 📜 Compliance Auditing
- **CloudTrail**: Enabled globally for all infrastructure changes.
- **Checkov** (is the infrastructure secure?): scans the HCL and workflows in CI and **every** `tfplan.json` at plan time. It blocks: no soft-fail anywhere. The settings live only in `.checkov.yaml`, and `make checkov` / the `checkov` pre-commit hook run the same command as CI, so a local pass is a CI pass. Accepted findings are inline `#checkov:skip=<ID>: <reason>` on the resource; the repo-wide `skip-check` list is only for checks that do not apply to this platform at all.
- **Trivy** (is the toolbox image free of known CVEs?): `publish-toolchain.yml` builds the image, scans it (`HIGH,CRITICAL`, fixable only, exit code 1) and pushes only if the scan passes. `make image-scan` does the same locally. `trivy config` (Terraform) still runs until PLAN 8.9 step 5 removes it, because Checkov now covers that job.
- **License Compliance**: Automated verification that all local modules include a standard open-source LICENSE, preventing legal risk and vendor lock-in.
