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

output "region_policy_ids" {
  description = "Map of OU name to that OU's region SCP ID (only the OUs that have one, PLAN 4.6)"
  value       = { for ou, p in aws_organizations_policy.deny_unapproved_regions : ou => p.id }
}

output "sandbox_guardrails_policy_id" {
  description = "ID of the Sandbox-only guardrail SCP, or null when enable_sandbox_guardrails is false"
  value       = try(aws_organizations_policy.sandbox_guardrails[0].id, null)
}

output "suspended_deny_all_policy_id" {
  description = "ID of the Suspended deny-all SCP, or null when enable_suspended_deny_all is false"
  value       = try(aws_organizations_policy.suspended_deny_all[0].id, null)
}
