# CI/CD, Governance & Self-Healing

All jobs run inside a purpose-built toolchain container (`ghcr.io/ok-karthik/infrastructure-toolchain`, defined in `.github/docker/Dockerfile`) so local and CI tool versions never drift.

## Pipeline (`terragrunt.yml` + `reusable-terragrunt.yml`)

1. **Static analysis** (parallel with planning): `terraform fmt -check`, `terraform validate`, TFLint, Checkov (HCL), Trivy. Results upload as SARIF to the GitHub Security tab.
2. **Plan** per environment: `terragrunt run --all plan` produces `tfplan.bin`, converted to `tfplan.json` and uploaded as an artifact.
3. **Governance gates** consume the plan JSON:
   - **OPA/Conftest** against `policies/terraform/` — mandatory tagging, no legacy instance families.
   - **Checkov** (plan-level, CIS benchmark) and **Trivy** (CRITICAL/HIGH) as blocking gates.
4. **Cost** — Infracost posts a per-module breakdown as a PR comment (`tf-summarize` adds a change summary).
5. **Apply** — on push to `main`, `apply-dev` runs, then `apply-prod`, which is gated by a protected GitHub **Environment** requiring manual approval.

A change can pass `terraform validate` and still fail the governance gates — the gates run against the *planned* resources, not just the HCL.

## Authentication — zero-key OIDC

Jobs assume short-lived IAM roles via GitHub Actions OIDC through the `setup-platform` composite action. No static AWS credentials exist in the repo or CI. There are **two roles**, so a pull request can never become admin:

| Role | Used by | Trusted OIDC subjects | Permissions |
|---|---|---|---|
| `github-actions-plan` | plan, governance and drift-detection jobs | `repo:<repo>:*` (any job of this repository, whatever the trigger; read-only, so this was widened from `pull_request` + `refs/heads/main` on purpose. Narrow it again if collaborators are added) | `ReadOnlyAccess`; on the state bucket: read state, write/delete `*.tflock` lock files only |
| `github-actions-apply` | `apply-dev`, `apply-prod`, `destroy` | `repo:<repo>:environment:<GitHubEnvironment>`, exactly one per account (`management` in the management account) | `AdministratorAccess` capped by the `github-actions-apply-boundary` permissions boundary (denies Identity Center, CloudTrail changes, organization destruction, edits to the boundary, the `github-actions-*` roles, the OIDC provider, the state bucket's settings and the bootstrap stack; also `organizations:*` / `account:*` everywhere except management). Narrowed further in PLAN 3.4 |

Both roles, the OIDC provider and the state bucket come from the Day-0 CloudFormation stack `platform-bootstrap` (`infrastructure-bootstrap/`, see its README).

Because the apply role trusts only one GitHub Environment, the manual-approval gate on that Environment cannot be bypassed from a branch or PR. **Today only the `management` account exists**, so create the `management` Environment (owner as required reviewer); its apply role trusts `environment:management` and nothing else.

**Repository variables** (Settings → Secrets and variables → Actions → Variables). `infrastructure-bootstrap/bootstrap.sh` prints the exact `gh` commands (it does not run them):

| Variable | Value |
|---|---|
| `AWS_REGION` | primary region, e.g. `eu-central-1` |
| `AWS_DEV_PLAN_ROLE_ARN` / `AWS_PROD_PLAN_ROLE_ARN` | ARN of `github-actions-plan`. Set both to the **management** plan role for now: plans are read-only, so they can stay there until `workloads-dev` exists |
| `AWS_DEV_APPLY_ROLE_ARN` / `AWS_PROD_APPLY_ROLE_ARN` | **Leave unset until a workload account exists.** The management apply role trusts only `environment:management`, so the dev/prod apply jobs cannot deploy workloads into the management account. This is intended. CI for the org stack (`_global`) comes with PLAN 2.6, and per-account Environments with it (until then `environment:dev` can apply to *any* NonProd account) |

The old `AWS_DEV_ROLE_ARN` / `AWS_PROD_ROLE_ARN` variables are no longer read and can be deleted.

**Account guard:** `root.hcl` takes the account ID from `account.hcl` (not from the caller's credentials) and sets it as `allowed_account_ids`, so running a stack with credentials for the wrong account fails at provider init.

## Governance rules (`policies/terraform/`)

- `require_tags.rego` — every created/updated resource must carry `Service`, `Environment`, `Project`, `Owner` and `DataClassification` (checked in `tags_all`; satisfied by `root.hcl` default tags, which read `owner` / `data_classification` from `account.hcl`).
- `no_legacy_instances.rego` — blocks `t2.`, `m3.`, `m4.`, `c3.`, `c4.` families.
- `deny_admin_attachments.rego` — `AdministratorAccess` / `IAMFullAccess` may only be attached to roles named `github-actions-apply*` or `break-glass*` (and the break-glass permission set).
- `deny_public_s3.rego` — S3 Block Public Access must be fully on; no `Principal: "*"` bucket policy without an `aws:PrincipalOrgID` condition.
- `deny_open_ingress.rego` — no `0.0.0.0/0` / `::/0` ingress on 22, 3389, 5432, 3306, 6379, 27017, 9200 (or all-traffic rules). Open 443 is *not* blocked: a plan cannot tell a public ALB security group from a private one.
- `deny_iam_wildcards.rego` — no `Allow` + `Action: "*"` + `Resource: "*"` in IAM policy documents (small named allow-list for permissions boundaries).
- `require_encryption.rego` — RDS `storage_encrypted`, EBS `encrypted` (volumes, instances, launch templates), S3 server-side encryption, SQS (SSE-SQS or KMS) and SNS (KMS).

Both are Rego v1 (`import rego.v1`, `package main`) and are unit-tested with `conftest verify` (see `*_test.rego`).

## Nightly drift detection (`drift-detection.yml`)

A matrix job over dev/prod compares live AWS against state each night and self-manages **one GitHub Issue per environment**: creates on new drift, comments while it persists, and auto-closes when resolved. Each env uses its own read-only plan role (`AWS_<ENV>_PLAN_ROLE_ARN`).

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
