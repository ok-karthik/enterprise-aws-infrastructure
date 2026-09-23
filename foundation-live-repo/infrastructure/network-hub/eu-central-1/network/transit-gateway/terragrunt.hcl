include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/transit-gateway.hcl"
  expose = true
}

# Transit gateway for eu-central-1. Order of the first rollout (owner): the network-hub account exists with a real id,
# the real Workloads/Infrastructure OU ARNs are filled in (\_envcommon/network/transit-gateway.hcl), the
# primary region (this one) applies before the
# secondary region (eu-west-1): the accepter needs the
# requester's peering attachment id. See the module README for accept_vpc_attachments (off through the first
# apply).
inputs = {}
