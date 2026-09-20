output "platform_admin_permission_set_arn" {
  description = "The ARN of the PlatformAdmin permission set"
  value       = try(aws_ssoadmin_permission_set.platform_admin[0].arn, null)
}

output "developer_permission_set_arn" {
  description = "The ARN of the Developer permission set"
  value       = try(aws_ssoadmin_permission_set.developer[0].arn, null)
}

output "auditor_permission_set_arn" {
  description = "The ARN of the AuditorReadOnly permission set"
  value       = try(aws_ssoadmin_permission_set.auditor[0].arn, null)
}

output "access_entry_arns" {
  description = "Map of EKS Access Entry ARNs created for teams"
  value       = { for k, v in aws_eks_access_entry.team : k => v.access_entry_arn }
}
