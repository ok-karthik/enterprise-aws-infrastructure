# The organization Access Analyzer (PLAN 3.6): external and unused access, in the security-tooling account (delegated administrator); applied by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/access-analyzer"
}

# Organization-wide Access Analyzer, created in the security-tooling account, which is the DELEGATED
# ADMINISTRATOR for access-analyzer.amazonaws.com. Order of the first rollout:
#   1. the account exists and has a real id (account factory, then the registry),
#   2. the organization stack registers it as delegated administrator (the org stack does that once the registry id is real),
#   3. then apply this stack, in every region you use (analyzers are regional).
# Findings reach Security Hub once Security Hub is enabled with this account as delegated administrator (PLAN 4.4).
inputs = {
  unused_access_age_days = 90

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
