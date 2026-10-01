# Common configuration for the "are the guardrails on?" alarms and dashboard (PLAN 9.3).
#   management account   : metric filters + alarms on the organization CloudTrail log group (create_alarms = true)
#   observability account: the dashboard only, reading the management account's metrics through OAM
# Applied by the owner. Which one this is comes from the account name.

terraform {
  source = local.module_source
}

locals {
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.guardrail_signals
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/observability/guardrail-signals" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/observability/guardrail-signals?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
  registry     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  is_mgmt      = local.account_name == "management"
}
