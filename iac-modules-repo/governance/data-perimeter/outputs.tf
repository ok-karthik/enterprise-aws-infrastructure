output "rcp_ids" {
  description = "Map of service short name to its RCP's policy ID"
  value       = { for s, p in aws_organizations_policy.data_perimeter : s => p.id }
}
