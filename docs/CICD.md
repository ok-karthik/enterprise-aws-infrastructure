# CI/CD, Governance & Self-Healing

All jobs run inside a purpose-built toolchain container (`ghcr.io/ok-karthik/infrastructure-toolchain`, defined in `.github/docker/Dockerfile`) so local and CI tool versions never drift.

## Pipeline (`terragrunt.yml` + `reusable-terragrunt.yml`)

1. **Static analysis** (parallel with planning): `terraform fmt -check`, `terraform validate`, TFLint, Checkov (HCL and workflows, blocking; run by `workloads-live-repo/scripts/run-checkov.sh`, the same wrapper as `make checkov` and pre-commit), Trivy (`trivy config`, until PLAN 8.9 step 5 removes it). Results upload as SARIF to the GitHub Security tab.
2. **Plan** per account (a matrix generated from the account registry, see below): `terragrunt run --all plan` produces `tfplan.bin`, converted to `tfplan.json` and uploaded as an artifact.
3. **Governance gates** consume the plan JSON:
   - **OPA/Conftest** against `policy-library-repo/terraform/` — mandatory tagging, no legacy instance families.
   - **Checkov** on **every** `tfplan.json` (one run per plan, SARIF merged into one file per account) and **Trivy** (CRITICAL/HIGH) as blocking gates. A run with no plan file fails instead of passing.

| Tool | Its one job | Locally | In CI |
|---|---|---|---|
| tflint | Terraform written correctly | `make lint` | static analysis |
| Checkov | Secure, general AWS best practice | pre-commit hook, `make checkov` | static (HCL) and plan (JSON) |
| conftest / Rego | This organization's own rules | `make test` | plan stage |
| Trivy | Toolbox image has no known fixable CVEs | `make image-scan` | `publish-toolchain.yml`, before the push |

   (`trivy config` on Terraform also still runs, until PLAN 8.9 step 5.)
4. **Cost** — Infracost posts a per-module breakdown as a PR comment (`tf-summarize` adds a change summary).
5. **Apply** — on push to `main`, `apply-dev` runs, then `apply-prod`, which is gated by a protected GitHub **Environment** requiring manual approval.

A change can pass `terraform validate` and still fail the governance gates — the gates run against the *planned* resources, not just the HCL.

## Module versions and promotion (dev → prod)

Live stacks do not read modules from the working tree. Each account's `env.hcl` has a `module_versions` map (for example `vpc = "vpc-v1.0.0"`), and each `_envcommon/<category>/<module>.hcl` builds its `terraform.source` from it:

```
git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/<category>/<module>?ref=<module>-vX.Y.Z
```

- **Release:** merging a `feat(<module>): ...` / `fix(<module>): ...` commit makes release-please open a release PR that tags `<module>-vX.Y.Z`.
- **Promote:** Renovate opens one PR per module and environment (`iac-modules: vpc pin (dev)`, then `... (prod)`), never automerged. Bump the pin in `workloads-live-repo/workloads-dev/env.hcl`, merge, check it; only then merge the prod PR. Dev and prod are separate PRs so the order is kept.
- **Test a module change before releasing it:** set `IAC_MODULES_LOCAL=1` to use the module from your checkout instead of the pinned tag. The workflows set it (and `workloads-live-repo/scripts/smoke-test.sh` defaults to it) **until every module has a release tag at the new `iac-modules-repo` path**: tags created before the rename (`vpc-v1.0.0`, ...) point at the old `infrastructure-modules` path. Release each module again (for example a `feat(<module>): relocate to iac-modules-repo` commit per module), then remove the variable from the workflows so the pins are used.

## Authentication — zero-key OIDC

Jobs assume short-lived IAM roles via GitHub Actions OIDC through the `setup-platform` composite action. No static AWS credentials exist in the repo or CI. There are **two roles**, so a pull request can never become admin:

| Role | Used by | Trusted OIDC subjects | Permissions |
|---|---|---|---|
| `github-actions-plan` | plan, governance and drift-detection jobs | `repo:<repo>:*` (any job of this repository, whatever the trigger; read-only, so this was widened from `pull_request` + `refs/heads/main` on purpose. Narrow it again if collaborators are added) | `ReadOnlyAccess`; on the state bucket: read state, write/delete `*.tflock` lock files only |
| `github-actions-apply` | the `apply` matrix job and `destroy` | `repo:<repo>:environment:<GitHubEnvironment>`, exactly one per account (`management` in the management account) | `AdministratorAccess` capped by the `github-actions-apply-boundary` permissions boundary (denies CloudTrail changes, organization destruction, switching off the security services, edits to the boundary, the `github-actions-*`, `platform-*` and `terraform-*` roles, the OIDC provider, the state bucket's settings and the bootstrap stack; also `organizations:*` / `account:*` and `sso:*` / `sso-directory:*` / `identitystore:*` everywhere except management, where the `AllowOrganizationsAdmin` and `AllowIdentityCenterAdmin` switches are on). The role itself is still `AdministratorAccess`: narrowing it to the services actually used is the open half of PLAN 3.4 |

Both roles, the OIDC provider and the state bucket come from the Day-0 CloudFormation stack `platform-bootstrap` (`foundation-live-repo/_bootstrap/`, see its README).

Because the apply role trusts only one GitHub Environment, the manual-approval gate on that Environment cannot be bypassed from a branch or PR. GitHub Environments: `management`, `core` (Security and Infrastructure accounts), `dev` and `prod` (with required reviewers). An account's apply role trusts only its own Environment; `dev` is shared by every NonProd account until one Environment per account is added (an optional later step: set the StackSet parameter per OU target).

## Account matrix: one job per account

Workflows do not have fixed `dev` / `prod` jobs. A `matrix` job runs `workloads-live-repo/scripts/generate_account_matrix.py`, which reads the account registry (`foundation-live-repo/_config/accounts.hcl`) and emits one entry per account that has `ci = true`, a live folder (`workloads-live-repo/<account>` or `foundation-live-repo/<account>`) and a **real account id** (a `000000000xxx` placeholder is skipped with a notice, never a red build). Plan, drift detection and apply all run over that matrix.

- **Role ARNs are built from the account id**: `arn:aws:iam::<account-id>:role/github-actions-plan` and `.../github-actions-apply`. There is no shared role, no role chaining, and no per-environment role variable. Each account has its own OIDC provider and roles from the Day-0 bootstrap (CloudFormation for management, StackSets for members), so the blast radius stays one account.
- **`stack`** (plan, governance, cost) runs for every account in parallel. **`apply`** runs on `main` only after every account's plan and governance passed, **one account at a time in the order management, core, dev, staging, prod**, and stops at the first failure. Each job runs in the account's GitHub Environment, so the approval on `prod` still gates prod.
- **`destroy.yml`** takes an `account` input, resolves it through the same script (so it only works for an account in the matrix) and refuses `management`.
- **Repository variable:** only `AWS_REGION`. `foundation-live-repo/_bootstrap/bootstrap.sh` prints the `gh` commands. The old `AWS_<ENV>_PLAN_ROLE_ARN` / `AWS_<ENV>_APPLY_ROLE_ARN` variables are no longer read and can be deleted.
- **Branch protection:** the required status checks are now named per account (for example `workloads-dev / 📝 Plan: workloads-dev`); update them in Settings → Branches (see `GOVERNANCE.md`). Until an account has a real id no plan job exists for it, so only static analysis runs.

**Account guard:** `root.hcl` takes the account ID from `account.hcl` (not from the caller's credentials) and sets it as `allowed_account_ids`, so running a stack with credentials for the wrong account fails at provider init.

## Governance rules (`policy-library-repo/terraform/`)

- `require_tags.rego` — every created/updated resource must carry `Service`, `Environment`, `Project`, `Owner` and `DataClassification` (checked in `tags_all`; satisfied by `root.hcl` default tags, which read `owner` / `data_classification` from `account.hcl`).
- `no_legacy_instances.rego` — blocks `t2.`, `m3.`, `m4.`, `c3.`, `c4.` families.
- `deny_admin_attachments.rego` — `AdministratorAccess` / `IAMFullAccess` may only be attached to roles named `github-actions-apply*` or `break-glass*` (and the break-glass permission set).
- `deny_public_s3.rego` — S3 Block Public Access must be fully on; no `Principal: "*"` bucket policy without an `aws:PrincipalOrgID` condition.
- `deny_open_ingress.rego` — no `0.0.0.0/0` / `::/0` ingress on 22, 3389, 5432, 3306, 6379, 27017, 9200 (or all-traffic rules). Open 443 is *not* blocked: a plan cannot tell a public ALB security group from a private one.
- `deny_iam_wildcards.rego` — no `Allow` + `Action: "*"` + `Resource: "*"` in IAM policy documents (small named allow-list for permissions boundaries).
- `require_encryption.rego` — RDS `storage_encrypted`, EBS `encrypted` (volumes, instances, launch templates), S3 server-side encryption, SQS (SSE-SQS or KMS) and SNS (KMS).

Both are Rego v1 (`import rego.v1`, `package main`) and are unit-tested with `conftest verify` (see `*_test.rego`).

## Nightly drift detection (`drift-detection.yml`)

A matrix job over the same account matrix compares live AWS against state each night and self-manages **one GitHub Issue per account**: creates on new drift, comments while it persists, and auto-closes when resolved. Each account's own read-only `github-actions-plan` role is used.

## Self-healing CI (`pipeline_healer.yml` + `.agents/`)

Triggered on a failed "Terragrunt CI/CD" run:

1. Downloads logs for the failed jobs only (GitHub Jobs API) to fit LLM token limits.
2. If it detects a provider-lock mismatch, runs `init -upgrade -backend=false` across all active `.terraform.lock.hcl` files (temporarily mocking `get_aws_account_id()` so parsing works without AWS creds) and commits the result.
3. Otherwise sends logs + repo tree to a Groq-hosted LLM, extracts a `git diff`, applies it, and pushes a remediation commit to the PR branch.

## Autonomous IaC Platform Agent & ChatOps (`chatops_generator.yml` + `.agents/`)

Provides on-demand self-service infrastructure generation, drift reconciliation, and Backstage IDP integration:
- Listens for `/generate` and `/reconcile` issue comments.
- Closed-loop drift reconciliation links nightly drift issues to corrective pull requests.
- See full architecture flow diagrams and usage guide in **[docs/IAC_PLATFORM_AGENT.md](IAC_PLATFORM_AGENT.md)**.

## Dependency automation

Renovate (`renovate.json`) tracks Terraform Registry modules (`tfr://`), toolchain binary versions in the Dockerfile ARGs, and GitHub Actions — grouping non-major bumps into a single PR and isolating majors for review.
