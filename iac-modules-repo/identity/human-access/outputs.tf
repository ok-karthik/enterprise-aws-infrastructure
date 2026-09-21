output "platform_engineer_permission_set_arn" {
  description = "The ARN of the PlatformEngineer permission set"
  value       = try(aws_ssoadmin_permission_set.platform_engineer[0].arn, null)
}

output "break_glass_permission_set_arn" {
  description = "The ARN of the BreakGlassAdmin permission set (not assigned to anyone by this module)"
  value       = try(aws_ssoadmin_permission_set.break_glass[0].arn, null)
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
