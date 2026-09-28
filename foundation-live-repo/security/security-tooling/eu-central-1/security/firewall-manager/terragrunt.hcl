include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/firewall-manager.hcl"
  expose = true
}

# FMS WAFv2 + SG audit policies, delegated to this (security-tooling) account.
# Prerequisites:
#   1. The security-tooling account exists with a real id in the account registry.
#   2. governance/organization registers it as delegated FMS admin:
#        delegated_administrators = { "fms.amazonaws.com" = "<security-tooling account id>" }
#   3. "fms.amazonaws.com" is in aws_service_access_principals.
#   4. Then apply this leaf.
inputs = {}
