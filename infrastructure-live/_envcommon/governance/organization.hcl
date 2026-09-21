# Common configuration for AWS Organizations governance across all environments.

terraform {
  source = "${get_repo_root()}/infrastructure-modules/governance/organization"
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env         = local.env_vars.locals.env
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  aws_region  = local.region_vars.locals.aws_region
}

inputs = {
  env                    = local.env
  region                 = local.aws_region
  publish_ssm_parameters = true

  # Region allow-list for the region SCP. Add a region here before workloads can use it.
  allowed_regions = ["eu-central-1"]

  tags = {
    Environment = title(local.env)
  }
}
