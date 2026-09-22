output "account_id" {
  description = "ID of the account this baseline was applied to"
  value       = local.account_id
}

output "workload_boundary_arn" {
  description = "ARN of platform-workload-boundary, which every role created by Terraform, ACK or tenants must carry"
  value       = aws_iam_policy.workload_boundary.arn
}

output "kms_general_key_arn" {
  description = "ARN of the CMK for general (internal) data"
  value       = aws_kms_key.general.arn
}

output "kms_confidential_key_arn" {
  description = "ARN of the CMK for confidential data"
  value       = aws_kms_key.confidential.arn
}

output "discovery_parameter_names" {
  description = "Names of the discovery parameters published in this account"
  value       = [for p in aws_ssm_parameter.discovery : p.name]
}

output "developer_policy_name" {
  description = "Name of the customer-managed policy the Developer permission set attaches (it must exist in every assigned account)"
  value       = aws_iam_policy.developer.name
}

output "security_remediation_role_arn" {
  description = "ARN of the security-remediation role, or null when security_remediation_lambda_role_arn is empty"
  value       = try(aws_iam_role.security_remediation[0].arn, null)
}
