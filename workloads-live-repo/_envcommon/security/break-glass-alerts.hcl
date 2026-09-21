# Common configuration for break-glass alerts (PLAN 3.3): an EventBridge rule per sign-in path for the
# BreakGlassAdmin permission set, an encrypted SNS topic and email subscriptions. Applied to EVERY account
# (regional, in the primary region); the management account also watches the Identity Center portal.
# Kept as an identical copy in foundation-live-repo and workloads-live-repo (separate repos cannot share a file).

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.break_glass_alerts
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/break-glass-alerts" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/break-glass-alerts?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name

  # The registry is the single source of truth for the account's email (in a real company the workloads
  # repo would read it from a pinned foundation release instead of the sibling folder).
  registry = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  account  = local.registry.locals.accounts[local.account_name]
}

inputs = {
  # Alerts go to the account's root email from the registry. The module refuses @example.com, so a
  # placeholder fails at plan time instead of alerting nobody. Each address must confirm the SNS
  # subscription once (a confirmation email arrives after the first apply).
  notification_emails = [local.account.email]

  # Only the management account sees the Identity Center portal calls (Federate / GetRoleCredentials).
  enable_sso_portal_rule = local.account_name == "management"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
