# Common configuration for VPC modules across all environments.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.vpc
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/network/vpc" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/network/vpc?ref=${local.module_version}"

  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env          = local.env_vars.locals.env
  cluster_name = local.env_vars.locals.cluster_name

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
}

inputs = {
  name         = "main-vpc-${local.env}"
  cluster_name = local.cluster_name

  # Standard subnet layout - Dynamic AZs based on region
  azs              = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets   = ["10.0.101.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

  # --- COST OPTIMIZATION / RESILIENCE: NAT settings come from env.hcl ---
  enable_nat_gateway = local.env_vars.locals.enable_nat_gateway
  single_nat_gateway = local.env_vars.locals.single_nat_gateway

  # Discovery contract
  env                    = local.env
  region                 = local.aws_region
  publish_ssm_parameters = true

  tags = {
    Environment = title(local.env)
  }
}
