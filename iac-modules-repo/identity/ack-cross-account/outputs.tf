output "spoke_role_arn" {
  description = "Spoke role ARN assumed by ACK controllers across accounts"
  value       = try(aws_iam_role.ack_spoke[0].arn, null)
}

output "ack_cross_account_ssm_parameter" {
  description = "SSM parameter path for ACK cross-account role ARN"
  value       = try(aws_ssm_parameter.ack_cross_account_role[0].name, null)
}

output "ack_tenant_boundary_arn" {
  description = "ARN of the permissions boundary every ACK-created role must carry"
  value       = try(aws_iam_policy.ack_tenant_boundary[0].arn, null)
}
