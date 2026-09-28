include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/network/central-endpoints.hcl"
  expose = true
}

# Shared interface endpoints. Order of the first rollout (owner):
#   1. the shared-services account exists and has a real id in _config/accounts.hcl and shared-services/account.hcl,
#   2. then apply this leaf,
#   3. once a workload account and its VPC exist, add it to spoke_vpcs (_envcommon/network/central-endpoints.hcl)
#      and re-apply, then create the matching aws_route53_zone_association in that workload account (not
#      built by this leaf; see the module README).
inputs = {}
