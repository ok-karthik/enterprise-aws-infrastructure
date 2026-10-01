include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/transit-gateway.hcl"
  expose = true
}

# Transit gateway for eu-west-1. Order of the first rollout (owner): the network-hub account exists with a real id and
# the real Workloads/Infrastructure OU ARNs are filled in (\_envcommon/network/transit-gateway.hcl). Cross-region
# peering is applied afterwards, in ../tgw-peering. See the module README for accept_vpc_attachments (off through
# the first apply).
inputs = {}
