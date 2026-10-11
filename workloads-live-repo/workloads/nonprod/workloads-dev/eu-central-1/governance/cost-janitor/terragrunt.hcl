# Report-only. Read the first weekly summary in CloudWatch Logs before setting dry_run = false. Dev only, never prod.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set (same pattern as _envcommon/governance/budgets.hcl).
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.cost_janitor
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/cost-janitor" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/cost-janitor?ref=${local.module_version}"
}

inputs = {
  dry_run = true

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
