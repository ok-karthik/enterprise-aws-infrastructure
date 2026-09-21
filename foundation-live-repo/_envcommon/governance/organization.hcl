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

  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env         = local.env_vars.locals.env
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
}

inputs = {
  env                    = local.env
  region                 = local.aws_region
  publish_ssm_parameters = true

  # Region allow-list for the region SCP. Add a region here before workloads can use it.
  allowed_regions = ["eu-central-1"]

  tags = {
    Environment = title(local.env)
  }
}
