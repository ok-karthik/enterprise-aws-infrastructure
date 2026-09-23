# Common configuration for the org-wide IPAM (PLAN 5.1), applied in network-hub. Applied by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.ipam
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/ipam" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/ipam?ref=${local.module_version}"

  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl")
  regions      = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl")
}

inputs = {
  organization_id = local.organization.locals.organization_id

  # TODO(owner): replace with the real Workloads OU ARN once governance/organization is applied and imported
  # (arn:aws:organizations::<management account id>:ou/<org id>/<workloads ou id>). The module refuses to
  # plan while this is not a well-formed OU ARN.
  workloads_ou_arn = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-00000000"

  operating_regions = [local.regions.locals.primary_region, local.regions.locals.secondary_region]

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
