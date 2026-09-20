terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. EKS Pod Identity (Primary Path)
# ------------------------------------------------------------------------------
resource "aws_eks_pod_identity_association" "this" {
  for_each = var.workload_identities

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account_name
  role_arn        = each.value.role_arn

  tags = merge(
    {
      Service   = "identity-workload-identity"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# 2. IRSA Fallback (For Fargate, non-AWS, or external workloads)
# ------------------------------------------------------------------------------
data "tls_certificate" "cluster_oidc" {
  count = var.oidc_issuer_url != "" ? 1 : 0
  url   = var.oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count           = var.oidc_issuer_url != "" ? 1 : 0
  url             = var.oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_oidc[0].certificates[0].sha1_fingerprint]

  tags = merge(
    {
      Service   = "identity-workload-identity"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

locals {
  oidc_provider_host = var.oidc_issuer_url != "" ? replace(var.oidc_issuer_url, "https://", "") : ""
}

resource "aws_iam_role" "irsa" {
  for_each = var.oidc_issuer_url != "" ? var.irsa_roles : {}

  name = "irsa-${each.value.namespace}-${each.value.service_account_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_host}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"
          "${local.oidc_provider_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(
    {
      Service   = "identity-workload-identity"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each = { for pair in flatten([
    for k, v in(var.oidc_issuer_url != "" ? var.irsa_roles : {}) : [
      for arn in v.policy_arns : { key = "${k}-${arn}", role_key = k, policy_arn = arn }
    ]
  ]) : pair.key => pair }

  role       = aws_iam_role.irsa[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
