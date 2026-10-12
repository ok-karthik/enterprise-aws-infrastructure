# Threat detection (PLAN 4.4): GuardDuty, Security Hub, Inspector v2 and Macie, organization-wide, applied in security-tooling (the delegated administrator for each service) by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/threat-detection"
}

# Order of the first rollout:
#   1. the security-tooling account exists and has a real id (account factory, then the registry),
#   2. the organization stack registers it as delegated administrator for each service (governance/organization,
#      delegated_administrators, applied from the management account),
#   3. then apply this stack, in every region in _config/regions.hcl's allow-list. This is the primary region
#      (is_primary_region = true), so it also creates the Security Hub finding aggregator.
inputs = {
  is_primary_region = include.root.locals.aws_region == include.root.locals.regions.primary_region

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
