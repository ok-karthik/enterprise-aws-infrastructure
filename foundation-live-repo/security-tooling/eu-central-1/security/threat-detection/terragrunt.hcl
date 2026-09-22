include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/threat-detection.hcl"
  expose = true
}

# Organization-wide GuardDuty, Security Hub, Inspector v2 and Macie, delegated to this (security-tooling)
# account. Order of the first rollout:
#   1. the security-tooling account exists and has a real id (account factory, then the registry),
#   2. the organization stack registers it as delegated administrator for each service (governance/organization,
#      delegated_administrators, applied from the management account),
#   3. then apply this leaf, in every region in _config/regions.hcl's allow-list. This is the primary region
#      (is_primary_region = true), so it also creates the Security Hub finding aggregator.
inputs = {}
