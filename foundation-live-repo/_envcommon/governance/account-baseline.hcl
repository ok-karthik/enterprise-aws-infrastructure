# Common configuration for the account baseline (PLAN 2.5): applied to EVERY account, in its
# primary region. Kept as an identical copy in foundation-live-repo and workloads-live-repo (separate
# repos cannot share a file).

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.account_baseline
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/account-baseline" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/account-baseline?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # security/auto-remediation's Lambda execution role (PLAN 4.9), by name, in the security-tooling account.
  # Left "" (creates nothing, governance/account-baseline's default) until security-tooling has a real id:
  # a role trusting a placeholder-account ARN would trust nobody real, and would need re-creating later anyway.
  registry                         = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  security_tooling_account_id      = local.registry.locals.accounts["security-tooling"].id
  auto_remediation_lambda_role_arn = !startswith(local.security_tooling_account_id, "00000000") ? "arn:aws:iam::${local.security_tooling_account_id}:role/auto-remediate-open-ssh-lambda" : ""
}

inputs = {
  account_alias = local.account_vars.locals.account_alias
  env           = local.account_vars.locals.env
  ou            = local.account_vars.locals.ou
  region        = local.region_vars.locals.aws_region

  security_remediation_lambda_role_arn = local.auto_remediation_lambda_role_arn

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
