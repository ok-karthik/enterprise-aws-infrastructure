# EKS cluster of the dev workload account. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/compute/eks"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-12345678"
    private_subnets = ["subnet-12345678", "subnet-87654321"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

locals {
  # --- SECURITY: the API endpoint is private unless this lists allowed CIDRs ---
  # Empty = private endpoint only (reach it from inside the VPC, e.g. SSM / VPN).
  # To use kubectl from a laptop, list explicit CIDRs, e.g. ["203.0.113.7/32"]. Never 0.0.0.0/0.
  api_allowed_cidrs = [] # TODO(owner): add your office/VPN egress CIDR(s) if you need public kubectl
}

inputs = {
  cluster_name       = "main-eks-dev"
  kubernetes_version = "1.30"

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # --- COST OPTIMIZATION: scaling ---
  # min_size is 0 and desired_size 1 so the night schedule is valid.
  min_size     = 0 # 0 so the night schedule can scale to zero (PLAN 9.5)
  max_size     = 2
  desired_size = 1

  # Optional night/weekend scale-down (PLAN 9.5). min_size must be 0 for the schedule to be valid.
  scale_schedule = {} # defaults: weekdays 07:00-19:00 Europe/Berlin

  # Fail closed: an empty api_allowed_cidrs list keeps the public endpoint disabled.
  cluster_endpoint_public_access = length(local.api_allowed_cidrs) > 0
  api_allowed_cidrs              = local.api_allowed_cidrs

  tags = {
    Environment = title(include.root.locals.env)
  }
}
