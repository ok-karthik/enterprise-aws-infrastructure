# Common configuration for EKS modules across all environments.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.eks
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/compute/eks" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/compute/eks?ref=${local.module_version}"

  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env          = local.env_vars.locals.env
  cluster_name = local.env_vars.locals.cluster_name

  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../../network/vpc" # Resolves relative to the live module directory

  mock_outputs = {
    vpc_id          = "vpc-12345678"
    private_subnets = ["subnet-12345678", "subnet-87654321"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  cluster_name       = local.cluster_name
  kubernetes_version = "1.30"

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # --- COST OPTIMIZATION: Dynamic Scaling ---
  min_size     = local.env_vars.locals.min_size
  max_size     = 3
  desired_size = local.env_vars.locals.desired_size

  # --- SECURITY: API endpoint is private unless env.hcl lists allowed CIDRs ---
  # Fail closed: an empty api_allowed_cidrs list keeps the public endpoint disabled.
  cluster_endpoint_public_access = length(local.env_vars.locals.api_allowed_cidrs) > 0
  api_allowed_cidrs              = local.env_vars.locals.api_allowed_cidrs

  # Discovery contract: published by the governance/discovery-publisher stack (one owner per name),
  # so the module must not publish the same parameters itself.
  env                    = local.env
  region                 = local.aws_region
  publish_ssm_parameters = false

  tags = {
    Environment = title(local.env)
  }
}
