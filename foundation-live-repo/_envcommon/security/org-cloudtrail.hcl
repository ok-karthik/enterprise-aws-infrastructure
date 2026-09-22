# Common configuration for the organization CloudTrail (PLAN 4.2): one multi-region trail, applied once in the
# management account, delivering to the bucket security/log-archive builds in the log-archive account. Applied
# by the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.org_cloudtrail
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/org-cloudtrail" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/org-cloudtrail?ref=${local.module_version}"

  registry     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")
  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl")

  # Same prefix and trail name as the log-archive leaf: the two build the same bucket name without either
  # reading the other's state.
  name_prefix = "platform"
  trail_name  = "platform-org-trail"
}

inputs = {
  trail_name = local.trail_name

  # <name_prefix>-cloudtrail-<log-archive account id>-<region>: the naming contract with security/log-archive
  # (see that module's README). Refused by the module while the account id is still a registry placeholder.
  log_archive_bucket_name = "${local.name_prefix}-cloudtrail-${local.registry.locals.accounts["log-archive"].id}-eu-central-1"
  kms_key_arn             = local.organization.locals.log_archive_kms_key_arn

  # TODO(owner): list the confidential (DataClassification=confidential) S3 bucket ARNs here once any exist,
  # to also log their S3 data events. Empty means management events only (the trail's default).
  confidential_s3_bucket_arns = []

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
