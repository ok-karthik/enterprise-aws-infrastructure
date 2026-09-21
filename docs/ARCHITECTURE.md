# Architecture

This platform follows a **Hierarchical Blueprint Pattern**: a generic, reusable Terraform library is kept strictly separate from live, per-environment configuration, so nothing is duplicated across environments.

## The two halves

- **`infrastructure-modules/`** — generic, reusable Terraform (`network/vpc`, `compute/eks`). Pure `.tf`, no environment specifics. Security hardening lives here, not just in CI.
- **`infrastructure-live/`** — Terragrunt configuration that composes those modules per environment and region.

## The inheritance chain

To understand any live module you read it top-down through these layers — a leaf `terragrunt.hcl` is often ~10 lines because it inherits everything else:

1. **`infrastructure-live/root.hcl`** — included by every leaf. Generates `provider.tf` and `backend.tf` at runtime and injects `default_tags` (`Environment`, `Service`, `Project`, `ManagedBy`, `Account`). The S3 backend bucket name and tags are computed here — modules never hand-write provider/backend blocks.
2. **`_envcommon/<category>/<module>.hcl`** — the shared blueprint per module type. Sets `terraform.source` (into `infrastructure-modules/`), declares `dependency` blocks with `mock_outputs` for plan-time, and default `inputs`. Cross-module wiring (EKS → VPC subnets) lives here.
3. **Data files** loaded via `find_in_parent_folders`:
   - `<env>/account.hcl` — account id (the account the stack is *allowed* to run in), alias, `owner`, `data_classification`
   - `<env>/env.hcl` — `env`, `cluster_name`, cost / resilience knobs (`min_size`, `desired_size`, `enable_nat_gateway`, `single_nat_gateway`) and `api_allowed_cidrs` (EKS public API allow-list; empty = private endpoint only)
   - `<env>/<region>/region.hcl` — `aws_region`
4. **Leaf** `<env>/<region>/<category>/<module>/terragrunt.hcl` — includes `root` + the matching `_envcommon` file and only overrides env-specific values (e.g. dev shrinks EKS node counts; prod runs `desired_size = 0`).

`path_relative_to_include()` drives naming everywhere — state key, the `Service` tag, env detection — so **directory layout is a contract, not a convention**. Allowed envs are `dev`/`prod`/`staging`; regions must be `eu-*`/`us-*` (enforced by `infrastructure-live/scripts/smoke-test.sh`).

## Bootstrap (day-0)

`infrastructure-bootstrap/` is a CloudFormation stack (`platform-bootstrap`) that must exist before `infrastructure-live` can deploy. It provisions the S3 state bucket, the GitHub OIDC identity provider, the `github-actions-apply` permissions boundary and the two CI roles (`github-actions-plan`, `github-actions-apply`) — i.e. the very backend and trust the live stacks depend on. CloudFormation is used here (not Terraform) because Terraform cannot create the bucket that holds its own state, and Terragrunt's `--backend-bootstrap` would create that bucket outside any state. `bootstrap.sh` refuses to run unless your credentials belong to the account in `infrastructure-live/_global/account.hcl`; member accounts get the same template through StackSets (PLAN 2.0b).

## State backend

Configured centrally in `root.hcl`: bucket `tg-state-<account-id>-<region>` per account/region, created by the bootstrap stack, with versioning (point-in-time rollback), native S3 lock files (`use_lockfile`, prevents concurrent-apply corruption), block-public-access, TLS 1.2+ only, and AES-256 SSE at rest.
