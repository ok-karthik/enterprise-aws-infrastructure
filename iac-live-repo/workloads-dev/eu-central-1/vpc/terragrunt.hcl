# The VPC of the dev workload account. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/vpc"
}

# CIDR is specific to this account and region.
locals {
  aws_region = include.root.locals.aws_region
}

inputs = {
  name         = "main-vpc-${include.root.locals.env}"
  cluster_name = "main-eks-dev"

  cidr             = "10.0.0.0/16"
  azs              = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets   = ["10.0.101.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

  # --- COST OPTIMIZATION / RESILIENCE ---
  enable_nat_gateway = true
  single_nat_gateway = true # one shared NAT is fine for dev; an AZ outage only affects dev egress

  tags = {
    Environment = title(include.root.locals.env)
  }
}
