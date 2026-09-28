include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/ipam.hcl"
  expose = true
}

# The org-wide IPAM. Order of the first rollout (owner):
#   1. the network-hub account exists and has a real id in _config/accounts.hcl and network-hub/account.hcl,
#   2. the real organization id is in _config/organization.hcl and the real Workloads OU id is filled in here,
#   3. turn on RAM sharing with AWS Organizations for the whole org (aws_ram_sharing_with_organization) --
#      a one-time, org-wide setting, not created by this module,
#   4. then apply this leaf.
inputs = {}
