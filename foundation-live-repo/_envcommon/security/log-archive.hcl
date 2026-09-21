# Common configuration for the central log archive (PLAN 4.1): Object Lock buckets for CloudTrail, Config, VPC flow logs,
# WAF, ALB, CloudFront and state-bucket access logs, in the log-archive account. Applied by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.log_archive
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/log-archive" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/log-archive?ref=${local.module_version}"

  registry     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl")
}

inputs = {
  # Both are refused by the module while they are placeholders, so a plan fails loudly instead of building
  # bucket policies for the wrong organization.
  organization_id       = local.organization.locals.organization_id
  management_account_id = local.registry.locals.accounts["management"].id

  # Same prefix and trail name as the org-cloudtrail leaf: together they make the CloudTrail bucket name a contract.
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
