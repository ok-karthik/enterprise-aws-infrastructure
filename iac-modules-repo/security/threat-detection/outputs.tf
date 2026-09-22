output "guardduty_detector_id" {
  description = "ID of this account's GuardDuty detector"
  value       = aws_guardduty_detector.this.id
}

output "securityhub_account_id" {
  description = "ID of the Security Hub account resource (this account's Security Hub subscription)"
  value       = aws_securityhub_account.this.id
}

output "finding_aggregator_arn" {
  description = "ARN of the Security Hub cross-region finding aggregator, or null outside the primary region"
  value       = try(aws_securityhub_finding_aggregator.this[0].arn, null)
}

output "inspector2_enabler_id" {
  description = "ID of the Inspector v2 enabler resource for this account"
  value       = aws_inspector2_enabler.this.id
}

output "macie_account_id" {
  description = "ID of the Macie account resource, or null when enable_macie is false"
  value       = try(aws_macie2_account.this[0].id, null)
}

output "detective_graph_arn" {
  description = "ARN of the Detective behavior graph, or null when enable_detective (or is_primary_region) is false"
  value       = try(aws_detective_graph.this[0].graph_arn, null)
}
