output "subscription_state" {
  description = "State of the Shield Advanced subscription (ACTIVE or empty if disabled)"
  value       = var.enabled ? "ACTIVE" : ""
}

output "protection_ids" {
  description = "Map of protection name => Shield protection ID"
  value       = { for k, p in aws_shield_protection.this : k => p.id }
}

output "protection_arns" {
  description = "Map of protection name => Shield protection ARN"
  value       = { for k, p in aws_shield_protection.this : k => p.arn }
}
