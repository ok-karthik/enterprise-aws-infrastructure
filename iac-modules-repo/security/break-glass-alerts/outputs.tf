output "topic_arn" {
  description = "ARN of the break-glass alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "rule_names" {
  description = "Names of the EventBridge rules"
  value       = [for r in aws_cloudwatch_event_rule.this : r.name]
}
