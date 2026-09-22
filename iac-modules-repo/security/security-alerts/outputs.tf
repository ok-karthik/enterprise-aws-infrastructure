output "topic_arn" {
  description = "ARN of the encrypted SNS topic every alert is published to"
  value       = aws_sns_topic.alerts.arn
}

output "enabled_rules" {
  description = "Names of the EventBridge rules this call created"
  value       = sort(keys(local.rules))
}
