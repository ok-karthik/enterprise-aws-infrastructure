# Common configuration for the account factory (PLAN 2.4): vends the member accounts listed in the
# registry with create = true. Applied from the management account only, by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.account_factory
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/account-factory" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/account-factory?ref=${local.module_version}"

  # The account registry is the single source of truth (foundation-live-repo/_config/accounts.hcl).
  registry = read_terragrunt_config("${dirname(find_in_parent_folders("root.hcl"))}/_config/accounts.hcl")
  accounts = local.registry.locals.accounts
}

# OU IDs come from the organization stack, which must be applied first.
dependency "organization" {
  config_path = "${get_terragrunt_dir()}/../organization"

  mock_outputs = {
    organizational_unit_ids = {
      "Security"       = "ou-0000-00000000"
      "Infrastructure" = "ou-0000-00000000"
      "Workloads"      = "ou-0000-00000000"
      "Prod"           = "ou-0000-00000000"
      "NonProd"        = "ou-0000-00000000"
      "Sandbox"        = "ou-0000-00000000"
      "Policy-Staging" = "ou-0000-00000000"
      "Suspended"      = "ou-0000-00000000"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  ou_ids = dependency.organization.outputs.organizational_unit_ids

  # Only entries with create = true. Placeholders and the management account are never vended.
  accounts = {
    for name, a in local.accounts : name => { email = a.email, ou = a.ou } if a.create
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
