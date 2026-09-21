output "account_ids" {
  description = "Map of account name to account ID"
  value       = { for name, a in aws_organizations_account.this : name => a.id }
}

output "account_arns" {
  description = "Map of account name to account ARN"
  value       = { for name, a in aws_organizations_account.this : name => a.arn }
}
