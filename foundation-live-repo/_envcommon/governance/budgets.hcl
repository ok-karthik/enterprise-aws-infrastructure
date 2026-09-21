# Common configuration for budgets (PLAN 2.8): a monthly cost budget per account with alerts at
# 50 / 80 / 100 % actual and 100 % forecast, plus Cost Anomaly Detection. Applied to EVERY account.
# The amount and the alert address come from the account registry. Kept as an identical copy in
# foundation-live-repo and workloads-live-repo (separate repos cannot share a file).

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.budgets
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/budgets" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/budgets?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name

  # The registry is the single source of truth (in a real company the workloads repo would read it
  # from a pinned foundation release instead of the sibling folder).
  registry = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  account  = local.registry.locals.accounts[local.account_name]
}

inputs = {
  account_name  = local.account_name
  monthly_limit = local.account.monthly_budget_usd

  # Alerts go to the account's root email from the registry. The module refuses @example.com, so a
  # placeholder fails at plan time instead of alerting nobody.
  notification_emails = [local.account.email]

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
