# The discovery publisher (PLAN 2.7): writes the platform discovery contract (/platform/<env>/<region>/...) into this account from the outputs of the stacks that own the values. Account and region come from the folder path (root.hcl).
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/governance/discovery-publisher"
}

# Publishes the VPC and EKS discovery parameters for this account. ack/cross_account_role_arn is added
# here once an ack-cross-account stack exists in the account.
# The VPC and EKS stacks do not publish their own parameters: this stack is the single owner of the names.
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id           = "vpc-12345678"
    database_subnets = ["subnet-12345678", "subnet-87654321"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-eks"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/MOCK"
    cluster_endpoint                   = "https://mock-eks.gr7.eu-central-1.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jYS1kYXRh"
    karpenter_node_iam_role_name       = "mock-eks-karpenter-node"
    karpenter_queue_name               = "mock-eks-karpenter"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "show"]
}

inputs = {
  env    = include.root.locals.env
  region = include.root.locals.aws_region

  parameters = merge(
    {
      "vpc/id"                = dependency.vpc.outputs.vpc_id
      "vpc/database_subnets"  = join(",", dependency.vpc.outputs.database_subnets)
      "eks/cluster_name"      = dependency.eks.outputs.cluster_name
      "eks/oidc_provider_arn" = dependency.eks.outputs.oidc_provider_arn
      "eks/cluster_endpoint"  = dependency.eks.outputs.cluster_endpoint
      "eks/cluster_ca_data"   = dependency.eks.outputs.cluster_certificate_authority_data
    },
    try(dependency.eks.outputs.karpenter_node_iam_role_name, null) != null && try(dependency.eks.outputs.karpenter_node_iam_role_name, "") != "" ? {
      "eks/karpenter_node_role" = dependency.eks.outputs.karpenter_node_iam_role_name
    } : {},
    try(dependency.eks.outputs.karpenter_queue_name, null) != null && try(dependency.eks.outputs.karpenter_queue_name, "") != "" ? {
      "eks/karpenter_queue_name" = dependency.eks.outputs.karpenter_queue_name
    } : {}
  )

  tags = {
    ManagedBy = "Terragrunt-Wrapper"
  }
}
