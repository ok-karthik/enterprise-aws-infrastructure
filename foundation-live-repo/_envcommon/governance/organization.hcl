# Common configuration for AWS Organizations governance across all environments.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.organization
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/organization" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/organization?ref=${local.module_version}"

  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env      = local.env_vars.locals.env

  # Delegated administrators: service => the registry account that administers it. Left out until that
  # account has a REAL id (registry placeholders are never registered). security-tooling is the delegated
  # administrator for access-analyzer (3.6) and for GuardDuty/Security Hub/Inspector v2/Macie (4.4,
  # security/threat-detection assumes this registration already happened).
  registry = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  delegated_administrator_accounts = {
    "access-analyzer.amazonaws.com" = "security-tooling"
    "guardduty.amazonaws.com"       = "security-tooling"
    "securityhub.amazonaws.com"     = "security-tooling"
    "inspector2.amazonaws.com"      = "security-tooling"
    "macie.amazonaws.com"           = "security-tooling"
  }
  delegated_administrators = {
    for service, account in local.delegated_administrator_accounts : service => local.registry.locals.accounts[account].id
    if !startswith(local.registry.locals.accounts[account].id, "00000000")
  }

  # Region allow-list per OU (PLAN 4.6), from _config/regions.hcl. Starts with ONLY the Policy-Staging entry,
  # same "test first" reasoning as guardrail_target_ous below: widen by adding more of
  # local.regions.locals.allowed_regions_by_ou's keys once Policy-Staging has been proven safe.
  regions = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl")
}

inputs = {
  allowed_regions_by_ou = {
    "Policy-Staging" = local.regions.locals.allowed_regions_by_ou["Policy-Staging"]
  }

  # The baseline SCPs attach to these OUs only. Start on Policy-Staging, test there, then widen
  # deliberately (for example ["Policy-Staging", "Sandbox", "NonProd"]). PLAN 4.6.
  guardrail_target_ous = ["Policy-Staging"]

  # Centralized root access (PLAN 3.5) is on by default; delegated administrators only once their account is real.
  enable_centralized_root_access = true
  delegated_administrators       = local.delegated_administrators

  tags = {
    Environment = title(local.env)
  }
}
