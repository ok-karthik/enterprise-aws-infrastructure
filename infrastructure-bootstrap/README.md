# 🚀 Platform Bootstrap Reference

This directory holds the "pre-CI/CD" infrastructure that everything else stands on: the S3 state bucket, the GitHub OIDC trust, and the IAM roles the pipeline assumes. It is applied **once, by a human**, with admin credentials for the target account. After that, CI takes over with short-lived OIDC credentials and no stored keys.

## What it creates

| Stack (`dev/_global/security/…`) | What | Why |
|---|---|---|
| *(state bucket)* | `tg-state-<account-id>-<alias>-<region>` | Created by Terragrunt (`--backend-bootstrap`) on the first run. Versioned, encrypted, public access blocked |
| `github-oidc-provider` | IAM OIDC provider for `token.actions.githubusercontent.com` | Lets GitHub jobs exchange their token for AWS credentials |
| `github-actions-boundary` | `github-actions-apply-boundary` permissions boundary | Caps the apply role: no organizations, Identity Center or CloudTrail changes, no edits to the CI roles, the OIDC provider or the boundary itself |
| `github-actions-plan` | Role for plan / governance / drift jobs | `ReadOnlyAccess`; on the state bucket it can read state and write/delete `*.tflock` lock files only. Trusts `pull_request` and `refs/heads/main` |
| `github-actions-apply` | Role for apply / destroy jobs | `AdministratorAccess` **with the boundary**. Trusts only the `dev` and `prod` GitHub Environments, so a branch or PR can never assume it |

## Guided bootstrap (recommended)

```bash
aws sso login                      # or any way of getting admin credentials for the target account
./infrastructure-bootstrap/bootstrap.sh
```

The script:

1. **Checks the account.** It compares the account your credentials belong to with `aws_account_id` in `dev/account.hcl` and stops if they differ. Nothing is created in the wrong account.
2. Shows the plan (this also creates the state bucket on the first run) and **asks before applying**. `--yes` skips the prompt.
3. Applies everything in dependency order.
4. Prints the exact `gh variable set` / `gh api` commands for the next step. It does not run them.

## Wire GitHub to the roles

Repository variables (Settings → Secrets and variables → Actions → **Variables**):

| Variable | Value |
|---|---|
| `AWS_REGION` | primary region, e.g. `eu-central-1` |
| `AWS_DEV_PLAN_ROLE_ARN`, `AWS_PROD_PLAN_ROLE_ARN` | `github-actions-plan` ARN |
| `AWS_DEV_APPLY_ROLE_ARN`, `AWS_PROD_APPLY_ROLE_ARN` | `github-actions-apply` ARN |

Dev and prod share one AWS account today, so they point at the same two roles. Create the `dev` and `prod` **GitHub Environments** (Settings → Environments) and add yourself as a required reviewer on `prod`: that is the manual approval gate, and the apply role only trusts jobs running in those environments.

We use repository *variables* rather than environment variables for the ARNs so `terragrunt plan` can run on pull requests without waiting on an environment approval.

## Manual steps (if you don't use the script)

```bash
cd infrastructure-bootstrap/dev
terragrunt run --all plan  --backend-bootstrap     # review
terragrunt run --all apply --backend-bootstrap
```

Check first that `aws sts get-caller-identity` shows the account in `dev/account.hcl`.

## Changing the account

The account is declared in **`account.hcl`** (`infrastructure-bootstrap/dev/`, `infrastructure-live/{dev,prod,_global}/`). `root.hcl` reads it for `allowed_account_ids` and for the state bucket name, so a mismatch with your credentials fails immediately instead of quietly targeting whichever account you happen to be logged in to.

Moving to a new account means: change `aws_account_id` in those files, log in to the new account, run `bootstrap.sh`, and update the repository variables. The new account gets a fresh state bucket, so there is nothing to migrate. Resources in the old account are untouched; remove them separately if you no longer want them.

## Migrating from the old single admin role

Earlier versions created one role, `github-actions-oidc-role`, that any branch or PR could assume with `AdministratorAccess`, and the pipeline read `AWS_DEV_ROLE_ARN` / `AWS_PROD_ROLE_ARN`. To retire it in an account that has it: run the bootstrap for the two new roles, set the four new variables, merge, then delete the old role (and the two old variables). The old stack no longer exists in this repo, so remove the role from the console, or with `terragrunt destroy` from a checkout of the previous commit.

## 🛠️ Toolchain & CI/CD architecture

The pipeline runs in a pre-packaged container (`ghcr.io/ok-karthik/infrastructure-toolchain`) so tool versions never drift.
* **Node.js 24**: all GitHub Actions used (`checkout`, `upload-artifact`, …) run on Node 24.
* **Runner compatibility**: the container runs as root (`options: --user root`) so the runner can write to the workspace (`/__w/_temp`) without `EACCES` errors.
