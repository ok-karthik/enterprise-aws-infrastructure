# Common configuration for the transit gateway (PLAN 5.2), applied in network-hub, once per region. The
# primary region is the peering "requester", the secondary region is the "accepter" (see network/transit-gateway's
# README): which one this call is is decided from _config/regions.hcl, not hardcoded per leaf.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.transit_gateway
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/transit-gateway" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/transit-gateway?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
  regions     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl")

  is_primary_region = local.aws_region == local.regions.locals.primary_region
}

inputs = {
  # TODO(owner): replace with the real Workloads / Infrastructure OU ARNs once governance/organization is
  # applied and imported. The module refuses to plan while these are not well-formed OU ARNs.
  workloads_ou_arn      = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-00000000"
  infrastructure_ou_arn = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-11111111"

  # Cross-region peering is disabled by default (role = "none") to avoid Terragrunt DAG dependency cycles
  # between regional transit gateways (primary <-> secondary). In a live deployment, peer attachment is
  # established in a second phase after both regional TGWs exist.
  peering = {
    role = "none"
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
