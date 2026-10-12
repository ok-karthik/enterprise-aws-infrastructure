# Cross-region transit gateway peering (PLAN 5.2), requester side, applied in network-hub by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/tgw-peering"
}

# The primary region is the peering "requester"; eu-west-1 (the secondary region) is the "accepter".
# Order of the first rollout (owner): both transit gateways (eu-central-1 and eu-west-1) are applied first, then
# this stack, then eu-west-1's tgw-peering (the accepter needs this stack's peering attachment id).
# Peering is its own stack so the two transit gateways never depend on each other.

# This region's transit gateway.
dependency "local_tgw" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock0123456789abcdef"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

# The other region's transit gateway, to peer to.
dependency "peer" {
  config_path = "../../eu-west-1/transit-gateway"

  mock_outputs = {
    transit_gateway_id    = "tgw-mock9876543210fedcba"
    peering_attachment_id = "tgw-attach-mock0123456789"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  role                    = "requester"
  transit_gateway_id      = dependency.local_tgw.outputs.transit_gateway_id
  peer_transit_gateway_id = dependency.peer.outputs.transit_gateway_id
  peer_region             = include.root.locals.regions.secondary_region

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
