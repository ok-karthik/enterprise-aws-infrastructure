# Common configuration for the discovery publisher (PLAN 2.7): writes the platform discovery contract
# (/platform/<env>/<region>/...) into THIS account from the outputs of the stacks that own the values.
# The VPC and EKS blueprints no longer publish their own parameters: this stack is the single owner of the names.

terraform {
  source = local.module_source
}

locals {
  # Module source: the pinned release tag (module_versions in env.hcl), or this checkout when
  # IAC_MODULES_LOCAL is set. CI sets it for PRs that change iac-modules-repo/** so module changes are
  # tested before release, and until every module has a release tag at the iac-modules-repo path.
  env_vars       = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  modules_local  = get_env("IAC_MODULES_LOCAL", "") != ""
  module_version = local.env_vars.locals.module_versions.discovery_publisher
  module_source  = local.modules_local ? "${get_repo_root()}/iac-modules-repo/governance/discovery-publisher" : "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/governance/discovery-publisher?ref=${local.module_version}"

  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../../network/vpc"

  mock_outputs = {
    vpc_id           = "vpc-12345678"
    database_subnets = ["subnet-12345678", "subnet-87654321"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

dependency "eks" {
  config_path = "${get_terragrunt_dir()}/../../compute/eks"

  mock_outputs = {
    cluster_name      = "mock-eks"
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  env    = local.account_vars.locals.env
  region = local.region_vars.locals.aws_region

  parameters = {
    "vpc/id"                = dependency.vpc.outputs.vpc_id
    "vpc/database_subnets"  = join(",", dependency.vpc.outputs.database_subnets)
    "eks/cluster_name"      = dependency.eks.outputs.cluster_name
    "eks/oidc_provider_arn" = dependency.eks.outputs.oidc_provider_arn
  }

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
