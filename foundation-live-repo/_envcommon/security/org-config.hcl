# Common configuration for organization-wide AWS Config (PLAN 4.3).
# Applied in security-tooling (delegated administrator for AWS Config).

terraform {
  source = local.module_source
}

locals {
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  module_version = try(local.env_vars.locals.module_versions.org_config, "v1.0.0")
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/security/org-config" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/org-config?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  regions     = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/regions.hcl")
  registry    = read_terragrunt_config("${get_repo_root()}/foundation-live-repo/_config/accounts.hcl")

  log_archive_id = local.registry.locals.accounts["log-archive"].id
}

inputs = {
  is_primary_region           = local.region_vars.locals.aws_region == local.regions.locals.primary_region
  allowed_regions             = [local.regions.locals.primary_region, local.regions.locals.secondary_region]
  config_delivery_bucket_name = "tg-log-archive-config-${local.log_archive_id}"

  enable_cis_conformance_pack         = true
  enable_nist_800_53_conformance_pack = true
  enable_soc2_conformance_pack        = true

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
