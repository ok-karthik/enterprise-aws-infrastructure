# Migration: one AWS account to a multi-account organization (2026)

**Status: a design and a set of tools, not yet a completed migration.** This file records what was actually done and what
it took, from the execution history and the code. The parts that need a real account (moving state,
downtime, what broke in AWS) are marked *not yet happened*. The owner adds them when they do; this is the story card
for PLAN 10.7, and it is the only migration story the repo can honestly tell so far.

## Where it started

One AWS account, `954171757349`, held everything: `dev` and `prod` Terragrunt stacks side by side, one shared state
bucket, and one broad `repo:*` admin role for CI. The environment came from the folder name.

## Where it ended up (in code)

An AWS Organization (`954171757349` became the **management** account) with OUs, and one account per job: security
(log-archive, security-tooling), infrastructure (network-hub, shared-services, observability) and workloads (dev, prod).
Every account gets its own state bucket, OIDC provider and two CI roles (plan, apply) from a Day-0 CloudFormation stack.

## What the move touched

| Thing | Before | After | Moved by |
|---|---|---|---|
| Folder layout | `dev/…`, `prod/…`, `_global/…` | `<account>/<region\|_global>/<category>/<module>`, under `foundation-live-repo/` and `workloads-live-repo/workloads/<nonprod\|prod>/` | `git mv`, in the PR |
| State key | path below `root.hcl`, e.g. `dev/eu-central-1/network/vpc` | starts with the account folder, e.g. `workloads-dev/eu-central-1/network/vpc` | `workloads-live-repo/scripts/migrate-state-keys.sh` (owner only) |
| State bucket | one bucket in `954171757349` | `tg-state-<account-id>-<region>` per account and region | created by the Day-0 stack |
| Environment | taken from the folder name | taken from `account.hcl` (`env`) | code |
| CI identity | one `repo:*` admin role | `github-actions-plan` (read-only) and `github-actions-apply` (one GitHub Environment, boundary-capped) in each account | Day-0 stack and StackSets |
| Account ID check | `get_aws_account_id()` (compared the caller with itself) | `allowed_account_ids` from `account.hcl` | code |

## What it took (facts)

- **Units moved in code:** every leaf under the old `dev/`, `prod/` and `_global/` folders. The migration script lists
  7 state moves.
- **State actually moved: none.** Nothing was applied to the new layout, so there was no state to move. The script
  (`migrate-state-keys.sh`) is dry-run by default and refuses to start while any account ID is a placeholder; it was tested
  against a stub with zero `aws` calls.
- **Downtime: none, because nothing was changed in AWS.**
- **Checks that guard the move:** the account registry check (`check-account-registry.sh`: folder name, ID, OU and env
  must match the registry), the smoke test (regions and envs from `_config/regions.hcl`), and the CI account matrix that
  skips placeholder accounts with a notice instead of a red build.

## What went wrong, or was found on the way

These were found by doing the work offline. They are the honest "what surprised me" list:

1. **The old bootstrap was already broken.** It used module names (`iam-github-oidc-role`, `iam-github-oidc-provider`) that do
   not exist in the pinned `terraform-aws-modules/iam` version. Found by validating the leaves against the real module.
2. **`allowed_account_ids` never failed.** It was built from `get_aws_account_id()`, which returns whichever account you are
   logged in to, so it compared the caller with itself.
3. **A `for_each` over values known only after apply** could never be created from scratch in the organization module's policy
   attachments. Found by a unit test; fixed with static keys.
4. **The state key changes with the folder layout**, and the `Service` tag is built from the same path. Any later reshuffle
   (for example adopting Terragrunt Stacks) is another state migration: this is why the ADR on stacks says "not yet".
5. **Terraform cannot create the bucket that holds its own state**, which is why Day-0 is CloudFormation and not Terraform.

## Not yet happened (owner)

- [ ] Real account IDs in `foundation-live-repo/_config/accounts.hcl` and the matching `account.hcl` files.
- [ ] Deploy the Day-0 stack in the management account and the StackSets for member accounts.
- [ ] Import the existing organization and OUs (`terragrunt import`, commands are in the live leaf).
- [ ] The first real plan in CI (PLAN 2.11).
- [ ] If any old state exists: run `migrate-state-keys.sh` (dry run first), and record here how long it took, how many state
  files moved and what went wrong.
