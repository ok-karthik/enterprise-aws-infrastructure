# Common configuration for IAM Identity Center (PLAN 3.1 / 3.2): permission sets, groups and account
# assignments. Applied from the management account only, by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.identity_center
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/identity/identity-center" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/identity/identity-center?ref=${local.module_version}"

  registry = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
}

inputs = {
  # Assignable accounts come from the registry: the management account and every vended account, but
  # only those with a REAL id (registry placeholders are left out until you fill them in).
  accounts = {
    for name, a in local.registry.locals.accounts : name => { id = a.id, ou = a.ou }
    if !startswith(a.id, "00000000") && (a.create || name == "management")
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
