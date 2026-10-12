# The VPC of the prod workload account, primary region. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/vpc"
}

# Production VPC uses a different CIDR range to avoid overlapping with dev.
locals {
  aws_region = include.root.locals.aws_region
}

inputs = {
  name         = "main-vpc-${include.root.locals.env}"
  cluster_name = "main-eks-prod"

  cidr             = "10.1.0.0/16"
  azs              = ["${local.aws_region}a", "${local.aws_region}b", "${local.aws_region}c"]
  private_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  public_subnets   = ["10.1.101.0/24"]
  database_subnets = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]

  # --- COST OPTIMIZATION / RESILIENCE: dormant prod, no NAT gateway for now ---
  enable_nat_gateway = false
  single_nat_gateway = false # one NAT per AZ, so a single AZ outage does not cut all prod egress (only takes effect when enable_nat_gateway = true)

  tags = {
    Environment = title(include.root.locals.env)
  }
}
