output "production_ou_id" {
  description = "The ID of the Production Organizational Unit"
  value       = try(aws_organizations_organizational_unit.production[0].id, null)
}

output "non_production_ou_id" {
  description = "The ID of the NonProduction Organizational Unit"
  value       = try(aws_organizations_organizational_unit.non_production[0].id, null)
}

output "spoke_role_arn" {
  description = "Spoke role ARN assumed by ACK controllers across accounts"
  value       = try(aws_iam_role.ack_spoke[0].arn, null)
}

output "ack_cross_account_ssm_parameter" {
  description = "SSM parameter path for ACK cross-account role ARN"
  value       = try(aws_ssm_parameter.ack_cross_account_role[0].name, null)
}
