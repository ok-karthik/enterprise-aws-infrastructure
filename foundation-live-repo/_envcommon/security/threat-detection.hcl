# Common configuration for threat detection (PLAN 4.4): GuardDuty, Security Hub, Inspector v2 and Macie,
# organization-wide, applied in security-tooling (the delegated administrator for each service). Applied by
# the owner, once per allowed region (region.hcl); is_primary_region is set from _config/regions.hcl.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.threat_detection
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/threat-detection" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/threat-detection?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  regions     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl")
}

inputs = {
  is_primary_region = local.region_vars.locals.aws_region == local.regions.locals.primary_region

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
