terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Human access to an EKS cluster: access entries and the cluster view policy.
# The IAM Identity Center permission sets (ReadOnly, Developer, PlatformEngineer, ...) moved to the
# identity/identity-center module, which owns the whole permission-set catalog and the assignments.

# ------------------------------------------------------------------------------
# EKS Access Entries & Cluster View Associations
# ------------------------------------------------------------------------------
resource "aws_eks_access_entry" "team" {
  for_each = var.cluster_name != "" ? var.team_access : {}

  cluster_name      = var.cluster_name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.k8s_groups
  type              = "STANDARD"

  tags = merge(
    {
      Service = "identity-human-access"
    },
    var.tags
  )
}

resource "aws_eks_access_policy_association" "team_view" {
  for_each = var.cluster_name != "" ? var.team_access : {}

  cluster_name  = var.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}
