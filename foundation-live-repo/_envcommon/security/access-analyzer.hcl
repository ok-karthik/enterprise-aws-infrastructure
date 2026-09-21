# Common configuration for the organization Access Analyzer (PLAN 3.6): external and unused access.
# Applied in the security-tooling account (delegated administrator), by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.access_analyzer
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/access-analyzer" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/access-analyzer?ref=${local.module_version}"
}

inputs = {
  unused_access_age_days = 90

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
