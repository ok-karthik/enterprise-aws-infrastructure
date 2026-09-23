include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/_envcommon/security/access-analyzer.hcl"
  expose = true
}

# Organization-wide Access Analyzer (external and unused access), created in the security-tooling account,
# which is the DELEGATED ADMINISTRATOR for access-analyzer.amazonaws.com. Order of the first rollout:
#   1. the account exists and has a real id (account factory, then the registry),
#   2. the organization stack registers it as delegated administrator (the org leaf does that once the registry id is real),
#   3. then apply this leaf, in every region you use (analyzers are regional).
# Findings reach Security Hub once Security Hub is enabled with this account as delegated administrator (PLAN 4.4).
inputs = {}
