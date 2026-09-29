include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/org-config.hcl"
  expose = true
}

# Organization-wide AWS Config (PLAN 4.3), delegated to this (security-tooling) account.
# Rollout prerequisites:
#   1. security-tooling account exists and has a real account ID in _config/accounts.hcl.
#   2. governance/organization registers config.amazonaws.com to security-tooling.
#   3. log-archive has created the config delivery bucket.
#   4. Apply this leaf in the primary region (creates aggregator and org conformance packs).
inputs = {}
