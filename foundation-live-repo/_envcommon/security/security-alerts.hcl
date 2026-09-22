# Common configuration for central security alerting (PLAN 4.5). Which rules are enabled depends on the
# account this is applied in (see the module README): security-tooling gets the GuardDuty/Security Hub
# rules (it is the delegated administrator, PLAN 4.4); management gets the root sign-in and SCP-change
# rules (root credentials and Organizations only exist there). Applied by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.security_alerts
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/security-alerts" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/security-alerts?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name

  # The registry is the single source of truth for the account's email (in a real company the workloads
  # repo would read it from a pinned foundation release instead of the sibling folder).
  registry = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  account  = local.registry.locals.accounts[local.account_name]
}

inputs = {
  notification_emails = [local.account.email]

  enable_guardduty_findings   = local.account_name == "security-tooling"
  enable_securityhub_findings = local.account_name == "security-tooling"
  enable_root_sign_in         = local.account_name == "management"
  enable_scp_changes          = local.account_name == "management"

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
