# Common configuration for CloudWatch cross-account observability (PLAN 9.1). In the observability account this
# creates the SINK; every other account links to it through governance/account-baseline (observability_sink_arn).
# Applied by the owner, after the observability account exists with a real id.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when IAC_MODULES_LOCAL is set.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.oam
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/observability/oam" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/observability/oam?ref=${local.module_version}"

  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl")
}

inputs = {
  mode            = "sink"
  organization_id = local.organization.locals.organization_id

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
