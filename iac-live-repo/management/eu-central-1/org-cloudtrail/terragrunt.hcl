# The organization CloudTrail (PLAN 4.2): one multi-region trail, applied once in the management account by the owner. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/security/org-cloudtrail"
}

# Delivers to the bucket security/log-archive builds in the log-archive account. Apply AFTER security/log-archive's
# first apply (its bucket policy must already accept this trail's name) and after the log-archive account id
# and organization id are real (_config/accounts.hcl, _config/organization.hcl). See the module README for the
# naming contract.
locals {
  # Same prefix and trail name as the log-archive stack: the two build the same bucket name without either
  # reading the other's state.
  name_prefix = "platform"
  trail_name  = "platform-org-trail"
}

inputs = {
  trail_name = local.trail_name

  # <name_prefix>-cloudtrail-<log-archive account id>-<region>: the naming contract with security/log-archive
  # (see that module's README). Refused by the module while the account id is still a registry placeholder.
  log_archive_bucket_name = "${local.name_prefix}-cloudtrail-${include.root.locals.registry["log-archive"].id}-eu-central-1"
  kms_key_arn             = include.root.locals.organization.log_archive_kms_key_arn

  # TODO(owner): list the confidential (DataClassification=confidential) S3 bucket ARNs here once any exist,
  # to also log their S3 data events. Empty means management events only (the trail's default).
  confidential_s3_bucket_arns = []

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
