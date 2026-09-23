# Common configuration for the shared interface endpoints (PLAN 5.4), applied in shared-services. Applied by
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
  module_version = local.env_vars.locals.module_versions.central_endpoints
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/central-endpoints" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/central-endpoints?ref=${local.module_version}"

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
}

inputs = {
  vpc_cidr            = "172.16.16.0/24" # distinct from IPAM's 10.0.0.0/8 and inspection-egress's 172.16.0.0/20
  azs                 = ["${local.aws_region}a", "${local.aws_region}b"]
  allowed_cidr_blocks = ["10.0.0.0/8"] # the platform's whole IPAM address space (network/ipam): every spoke VPC, without listing each one

  # TODO(owner): once workload accounts exist and their VPC ids/regions are known, list them here so their
  # zone associations can be authorized. Empty means no spoke is authorized yet (each service's zone is
  # created and usable from THIS account only).
  spoke_vpcs = []

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
