output "instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "ID of the Identity Center identity store"
  value       = local.identity_store_id
}

output "permission_set_arns" {
  description = "Map of permission set name to ARN"
  value       = { for name, ps in aws_ssoadmin_permission_set.this : name => ps.arn }
}

output "group_ids" {
  description = "Map of group name to identity store group ID"
  value       = local.group_ids
}

output "assignment_keys" {
  description = "Every account/group/permission-set assignment that exists"
  value       = sort(keys(aws_ssoadmin_account_assignment.this))
}
