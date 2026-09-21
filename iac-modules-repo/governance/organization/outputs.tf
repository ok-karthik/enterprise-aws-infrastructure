output "organization_id" {
  description = "ID of the AWS Organization (o-...)"
  value       = aws_organizations_organization.this.id
}

output "root_id" {
  description = "ID of the organization root (r-...)"
  value       = aws_organizations_organization.this.roots[0].id
}

output "management_account_id" {
  description = "Account ID of the management account"
  value       = aws_organizations_organization.this.master_account_id
}

output "organizational_unit_ids" {
  description = "Map of OU name to OU ID (ou-...)"
  value       = local.organizational_unit_ids
}

output "guardrail_policy_ids" {
  description = "Map of guardrail name to SCP ID"
  value       = local.guardrail_policy_ids
}

output "centralized_root_access_enabled" {
  description = "Whether centralized root access management is enabled"
  value       = var.enable_centralized_root_access
}

output "delegated_administrators" {
  description = "Delegated administrator accounts, keyed by service principal"
  value       = { for principal, d in aws_organizations_delegated_administrator.this : principal => d.account_id }
}
