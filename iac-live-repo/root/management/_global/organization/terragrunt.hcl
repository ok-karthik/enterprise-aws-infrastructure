# The AWS Organization: OU tree, baseline SCP guardrails and delegated administrators; applied by the owner from the management account. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/organization"
}

locals {
  env      = include.root.locals.env
  registry = include.root.locals.registry
  regions  = include.root.locals.regions

  # Delegated administrators: service => the registry account that administers it. Left out until that
  # account has a REAL id (registry placeholders are never registered). security-tooling is the delegated
  # administrator for access-analyzer (3.6) and for GuardDuty/Security Hub/Inspector v2/Macie (4.4,
  # security/threat-detection assumes this registration already happened).
  delegated_administrator_accounts = {
    "access-analyzer.amazonaws.com"          = "security-tooling"
    "guardduty.amazonaws.com"                = "security-tooling"
    "securityhub.amazonaws.com"              = "security-tooling"
    "inspector2.amazonaws.com"               = "security-tooling"
    "macie.amazonaws.com"                    = "security-tooling"
    "config.amazonaws.com"                   = "security-tooling"
    "config-multiaccountsetup.amazonaws.com" = "security-tooling"
    "auditmanager.amazonaws.com"             = "security-tooling"
  }
  delegated_administrators = {
    for service, account in local.delegated_administrator_accounts : service => local.registry[account].id
    if !startswith(local.registry[account].id, "00000000")
  }
}

inputs = {
  # The OU tree, from _config/organization.hcl (one source; the live folders mirror it).
  organizational_units = include.root.locals.organization.organizational_units

  # Region allow-list per OU (PLAN 4.6), from _config/regions.hcl. Starts with ONLY the Policy-Staging entry,
  # same "test first" reasoning as guardrail_target_ous below: widen by adding more of
  # local.regions.allowed_regions_by_ou's keys once Policy-Staging has been proven safe.
  allowed_regions_by_ou = {
    "Policy-Staging" = local.regions.allowed_regions_by_ou["Policy-Staging"]
  }

  # Default target OUs for guardrails not explicitly mapped in policy_targets.
  # Starts with Policy-Staging only (PLAN 4.6).
  guardrail_target_ous = ["Policy-Staging"]

  # Pattern A: Progressive per-policy rollout across OUs.
  # To promote a policy to wider OUs (e.g., Sandbox, NonProd, Prod), add the OU name to its list.
  # New or experimental policies can remain on ["Policy-Staging"] only.
  # Any guardrail omitted from this map falls back to guardrail_target_ous.
  policy_targets = {
    deny_leave_org                      = ["Policy-Staging"]
    deny_disable_cloudtrail             = ["Policy-Staging"]
    deny_root_user_actions              = ["Policy-Staging"]
    deny_disable_detection_services     = ["Policy-Staging"]
    deny_iam_user_creation              = ["Policy-Staging"]
    protect_platform_resources          = ["Policy-Staging"]
    require_imdsv2                      = ["Policy-Staging"]
    deny_role_creation_without_boundary = ["Policy-Staging"]
  }

  # Centralized root access (PLAN 3.5) is on by default; delegated administrators only once their account is real.
  enable_centralized_root_access = true
  delegated_administrators       = local.delegated_administrators

  tags = {
    Environment = title(local.env)
  }
}
