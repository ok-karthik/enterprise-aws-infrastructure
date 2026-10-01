include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/tgw-peering.hcl"
  expose = true
}

# Peering requester for eu-central-1 (the primary region). Order of the first rollout (owner): both transit gateways
# (eu-central-1 and eu-west-1) are applied first, then this unit, then eu-west-1's tgw-peering (the accepter needs
# this unit's peering attachment id).
inputs = {}
