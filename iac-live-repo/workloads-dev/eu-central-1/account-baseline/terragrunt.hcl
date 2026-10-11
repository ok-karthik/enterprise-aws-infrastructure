# The account baseline (PLAN 2.5), applied to every account in its primary region. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/account-baseline"
}

# The account baseline: account alias, password policy, S3 Block Public Access, EBS encryption and IMDSv2
# defaults, the KMS keys, platform-workload-boundary and the account discovery parameters.
# The state bucket and the CI roles are NOT here: they come from the Day-0 bootstrap stack.
locals {
  # security/auto-remediation's Lambda execution role (PLAN 4.9), by name, in the security-tooling account.
  # Left "" (creates nothing, governance/account-baseline's default) until security-tooling has a real id:
  # a role trusting a placeholder-account ARN would trust nobody real, and would need re-creating later anyway.
  security_tooling_account_id      = include.root.locals.registry["security-tooling"].id
  auto_remediation_lambda_role_arn = !startswith(local.security_tooling_account_id, "00000000") ? "arn:aws:iam::${local.security_tooling_account_id}:role/auto-remediate-open-ssh-lambda" : ""
}

inputs = {
  account_alias = include.root.locals.alias
  env           = include.root.locals.env
  ou            = include.root.locals.ou
  region        = include.root.locals.aws_region

  security_remediation_lambda_role_arn = local.auto_remediation_lambda_role_arn

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
