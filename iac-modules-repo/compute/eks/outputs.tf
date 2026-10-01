output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_id" {
  description = "The name of the EKS cluster. Works for both existing and new clusters"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = module.eks.oidc_provider_arn
}

output "karpenter_node_iam_role_arn" {
  description = "The ARN of the IAM role for Karpenter nodes"
  value       = try(module.karpenter[0].node_iam_role_arn, null)
}

output "karpenter_node_iam_role_name" {
  description = "The name of the IAM role for Karpenter nodes"
  value       = try(module.karpenter[0].node_iam_role_name, null)
}

output "karpenter_queue_name" {
  description = "The name of the SQS interruption queue for Karpenter"
  value       = try(module.karpenter[0].queue_name, null)
}

output "karpenter_queue_arn" {
  description = "The ARN of the SQS interruption queue for Karpenter"
  value       = try(module.karpenter[0].queue_arn, null)
}
