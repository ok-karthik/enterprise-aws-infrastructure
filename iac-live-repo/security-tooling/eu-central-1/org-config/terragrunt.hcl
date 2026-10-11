# Organization-wide AWS Config (PLAN 4.3), delegated to the security-tooling account. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/org-config"
}

# Rollout prerequisites:
#   1. security-tooling account exists and has a real account ID in _config/accounts.hcl.
#   2. governance/organization registers config.amazonaws.com to security-tooling.
#   3. log-archive has created the config delivery bucket.
#   4. Apply this stack in the primary region (creates aggregator and org conformance packs).
inputs = {
  is_primary_region           = include.root.locals.aws_region == include.root.locals.regions.primary_region
  allowed_regions             = [include.root.locals.regions.primary_region, include.root.locals.regions.secondary_region]
  config_delivery_bucket_name = "tg-log-archive-config-${include.root.locals.registry["log-archive"].id}"

  enable_cis_conformance_pack         = true
  enable_nist_800_53_conformance_pack = true
  enable_soc2_conformance_pack        = true

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
