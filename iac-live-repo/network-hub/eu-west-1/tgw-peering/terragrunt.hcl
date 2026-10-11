# Cross-region transit gateway peering (PLAN 5.2), accepter side, applied in network-hub by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/tgw-peering"
}

# The secondary region is the peering "accepter"; eu-central-1 (the primary region) is the "requester".
# Order of the first rollout (owner): both transit gateways (eu-central-1 and eu-west-1) and eu-central-1's
# tgw-peering (the requester) are applied first.
# Peering is its own stack so the two transit gateways never depend on each other.

# This region's transit gateway (not an input here, but it must exist before the peering is accepted).
dependency "local_tgw" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock0123456789abcdef"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

# The primary region's peering stack, for the attachment to accept.
dependency "peer" {
  config_path = "../../eu-central-1/tgw-peering"

  mock_outputs = {
    transit_gateway_id    = "tgw-mock9876543210fedcba"
    peering_attachment_id = "tgw-attach-mock0123456789"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  role                  = "accepter"
  peering_attachment_id = dependency.peer.outputs.peering_attachment_id

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
