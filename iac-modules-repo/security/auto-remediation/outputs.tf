output "lambda_function_arn" {
  description = "ARN of the auto-remediation Lambda"
  value       = aws_lambda_function.remediate_open_ssh.arn
}

output "event_bus_arn" {
  description = "ARN of the central event bus that member accounts forward AuthorizeSecurityGroupIngress events to"
  value       = aws_cloudwatch_event_bus.central.arn
}

output "event_bus_name" {
  description = "Name of the central event bus (member-account forwarding rules, added by governance/account-baseline, target this by name)"
  value       = aws_cloudwatch_event_bus.central.name
}
