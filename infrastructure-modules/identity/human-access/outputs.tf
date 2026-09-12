output "platform_admin_permission_set_arn" {
  description = "The ARN of the PlatformAdmin permission set"
  value       = aws_ssoadmin_permission_set.platform_admin.arn
}

output "developer_permission_set_arn" {
  description = "The ARN of the Developer permission set"
  value       = aws_ssoadmin_permission_set.developer.arn
}

output "auditor_permission_set_arn" {
  description = "The ARN of the AuditorReadOnly permission set"
  value       = aws_ssoadmin_permission_set.auditor.arn
}
