# The central log archive (PLAN 4.1): Object Lock buckets for CloudTrail, Config, VPC flow logs, WAF, ALB, CloudFront and state-bucket access logs; applied in the log-archive account by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/log-archive"
}

# Order of the first rollout (owner):
#   1. the log-archive account exists and has a real id in iac-live-repo/_config/accounts.hcl,
#   2. the real organization id is in _config/organization.hcl,
#   3. the Day-0 bootstrap stack ran in the account (state bucket), then apply this stack,
#   4. copy `kms_key_arn` from the output into iac-live-repo/_config/organization.hcl (log_archive_kms_key_arn),
#      which the org-cloudtrail stack in the management account reads.
# COMPLIANCE Object Lock cannot be undone. Read the module README before the first apply.
inputs = {
  # Both are refused by the module while they are placeholders, so a plan fails loudly instead of building
  # bucket policies for the wrong organization.
  organization_id       = include.root.locals.organization.organization_id
  management_account_id = include.root.locals.registry["management"].id

  # Same prefix and trail name as the org-cloudtrail stack: together they make the CloudTrail bucket name a contract.
  name_prefix = "platform"
  trail_name  = "platform-org-trail"

  # 400 days for the audit trail and Config, 90 for the rest. COMPLIANCE lock: cannot be undone (see the module README).
  # Use GOVERNANCE while you are only experimenting in a sandbox.
  object_lock_mode = "COMPLIANCE"
  retention_days = {
    cloudtrail = 400
    config     = 400
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
