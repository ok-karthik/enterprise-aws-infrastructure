output "access_entry_arns" {
  description = "Map of EKS Access Entry ARNs created for teams"
  value       = { for k, v in aws_eks_access_entry.team : k => v.access_entry_arn }
}
