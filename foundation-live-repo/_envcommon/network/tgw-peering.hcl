# Common configuration for cross-region transit gateway peering (PLAN 5.2), applied in network-hub, once per region.
# The primary region is the peering "requester", the secondary region is the "accepter" (see network/tgw-peering's
# README): which one this call is is decided from _config/regions.hcl, not hardcoded per leaf.
#
# Order: both transit gateways, then the primary region's peering (requester), then the secondary region's (accepter).
# Peering is its own unit so the two transit gateways never depend on each other.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.tgw_peering
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/tgw-peering" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/tgw-peering?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
  regions     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl")

  is_primary_region = local.aws_region == local.regions.locals.primary_region
}

# This region's transit gateway (the leaf is <region>/network/tgw-peering, so it is a sibling folder).
dependency "local_tgw" {
  config_path = "${get_terragrunt_dir()}/../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock0123456789abcdef"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

# The other region's unit. Primary (requester): the secondary region's transit gateway, to peer to. Secondary
# (accepter): the primary region's peering unit, for the attachment to accept. Three ".." get from the leaf to the
# network-hub folder.
dependency "peer" {
  config_path = local.is_primary_region ? "${get_terragrunt_dir()}/../../../${local.regions.locals.secondary_region}/network/transit-gateway" : "${get_terragrunt_dir()}/../../../${local.regions.locals.primary_region}/network/tgw-peering"

  mock_outputs = {
    transit_gateway_id    = "tgw-mock9876543210fedcba"
    peering_attachment_id = "tgw-attach-mock0123456789"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  # Every key present in both branches (even as null): the ternary's two branches must share one object
  # shape (HCL type unification).
  role                    = local.is_primary_region ? "requester" : "accepter"
  transit_gateway_id      = local.is_primary_region ? dependency.local_tgw.outputs.transit_gateway_id : null
  peer_transit_gateway_id = local.is_primary_region ? dependency.peer.outputs.transit_gateway_id : null
  peer_region             = local.is_primary_region ? local.regions.locals.secondary_region : null
  peering_attachment_id   = local.is_primary_region ? null : dependency.peer.outputs.peering_attachment_id

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
