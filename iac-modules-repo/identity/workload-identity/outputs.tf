output "associations" {
  description = "Map of EKS Pod Identity association IDs"
  value       = { for k, v in aws_eks_pod_identity_association.this : k => v.association_id }
}

output "irsa_role_arns" {
  description = "Map of IAM role ARNs created for the IRSA fallback path"
  value       = { for k, v in aws_iam_role.irsa : k => v.arn }
}

output "oidc_provider_arn" {
  description = "The ARN of the IAM OIDC provider created for IRSA"
  value       = try(aws_iam_openid_connect_provider.cluster[0].arn, null)
}
