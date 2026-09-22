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

# The OTHER region's transit gateway. The primary region's leaf (requester) needs its id to peer to; the
# secondary region's leaf ignores this dependency's transit_gateway_id and only uses its peering_attachment_id.
dependency "peer_transit_gateway" {
  config_path = "${get_terragrunt_dir()}/../../${local.is_primary_region ? local.regions.locals.secondary_region : local.regions.locals.primary_region}/network/transit-gateway"

  mock_outputs = {
    transit_gateway_id    = "tgw-mock0123456789abcdef"
    peering_attachment_id = "tgw-attach-mock0123456789"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  # TODO(owner): replace with the real Workloads / Infrastructure OU ARNs once governance/organization is
  # applied and imported. The module refuses to plan while these are not well-formed OU ARNs.
  workloads_ou_arn      = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-00000000"
  infrastructure_ou_arn = "arn:aws:organizations::000000000000:ou/o-0000000000/ou-0000-11111111"

  # Every key present in both branches (even as null): the ternary's two branches must share one object
  # shape (HCL type unification), even though the module's own variable type makes each key optional.
  peering = local.is_primary_region ? {
    role                    = "requester"
    peer_transit_gateway_id = dependency.peer_transit_gateway.outputs.transit_gateway_id
    peer_region             = local.regions.locals.secondary_region
    peer_account_id         = null
    accepter_attachment_id  = null
    } : {
    role                    = "accepter"
    peer_transit_gateway_id = null
    peer_region             = null
    peer_account_id         = null
    accepter_attachment_id  = dependency.peer_transit_gateway.outputs.peering_attachment_id
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
