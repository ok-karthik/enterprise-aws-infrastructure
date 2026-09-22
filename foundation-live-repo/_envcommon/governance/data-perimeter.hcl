# Common configuration for the data perimeter (PLAN 4.6): Resource Control Policies for S3, KMS, SQS and
# Secrets Manager (sts is opt-in, see the module README), applied from the management account. Applied by
# the owner.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.data_perimeter
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/data-perimeter" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/data-perimeter?ref=${local.module_version}"

  organization = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/organization.hcl")
}

inputs = {
  organization_id = local.organization.locals.organization_id

  # TODO(owner): replace with the real Policy-Staging OU id once governance/organization is applied and
  # imported (same placeholder-OU-id situation as bootstrap-stacksets; look it up the same way, or read it
  # from governance/organization's organizational_unit_ids output). The module refuses to attach to an OU
  # that is not a key of this map.
  target_ou_ids = {
    "Policy-Staging" = "ou-0000-00000000"
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
