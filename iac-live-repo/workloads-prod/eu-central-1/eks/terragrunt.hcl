# EKS cluster of the prod workload account, primary region. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/compute/eks"
}

# Dormant prod: mirrors dev scaling, with a slightly higher default for prod parity.
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
  cluster_name       = "main-eks-prod"
  kubernetes_version = "1.30"

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # --- COST OPTIMIZATION: scaling ---
  min_size     = 1
  max_size     = 3
  desired_size = 2 # Slightly higher default for prod parity

  # Fail closed: an empty api_allowed_cidrs list keeps the public endpoint disabled.
  cluster_endpoint_public_access = length(local.api_allowed_cidrs) > 0
  api_allowed_cidrs              = local.api_allowed_cidrs

  tags = {
    Environment = title(include.root.locals.env)
  }
}
