# Role assumed by CI jobs that only PLAN (pull requests, pushes to main, nightly drift detection).
# Read-only on AWS. On the state bucket it can read state and write/delete lock files, so
# `terraform plan` works, but it cannot modify state itself.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/iam/aws//modules/iam-role?version=6.6.0"
}

# The GitHub OIDC provider must exist before a role can trust it.
dependencies {
  paths = ["../github-oidc-provider"]
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # The GitHub repository that is allowed to assume this role
  github_repo = "ok-karthik/enterprise-aws-infrastructure"

  # Must match the bucket name root.hcl generates for every stack in this account
  state_bucket = "tg-state-${local.account_vars.locals.aws_account_id}-${local.account_vars.locals.account_name}-${local.region_vars.locals.aws_region}"
}

inputs = {
  name            = "github-actions-plan"
  use_name_prefix = false
  description     = "GitHub Actions: terragrunt plan (read-only)"

  # 1 hour is plenty for a plan job
  max_session_duration = 3600

  enable_github_oidc = true
  oidc_subjects = [
    "${local.github_repo}:pull_request",
    "${local.github_repo}:ref:refs/heads/main",
  ]

  policies = {
    ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  create_inline_policy = true
  inline_policy_permissions = {
    StateBucketList = {
      actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
      resources = ["arn:aws:s3:::${local.state_bucket}"]
    }
    StateRead = {
      actions   = ["s3:GetObject", "s3:GetObjectVersion"]
      resources = ["arn:aws:s3:::${local.state_bucket}/*"]
    }
    # use_lockfile = true: Terraform creates and deletes <key>.tflock next to the state file.
    StateLockWrite = {
      actions   = ["s3:PutObject", "s3:DeleteObject"]
      resources = ["arn:aws:s3:::${local.state_bucket}/*.tflock"]
    }
  }

  tags = {
    Role = "github-actions-plan"
  }
}
