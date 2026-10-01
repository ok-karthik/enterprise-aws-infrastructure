include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/tgw-peering.hcl"
  expose = true
}

# Peering accepter for eu-west-1 (the secondary region). Order of the first rollout (owner): both transit gateways
# (eu-central-1 and eu-west-1) and eu-central-1's tgw-peering (the requester) are applied first.
inputs = {}
