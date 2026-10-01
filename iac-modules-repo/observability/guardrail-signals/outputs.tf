output "alarm_arns" {
  description = "ARNs of the guardrail alarms (empty when create_alarms is false)"
  value       = [for a in aws_cloudwatch_metric_alarm.this : a.arn]
}

output "signal_names" {
  description = "Names of the signals (metric names in the Platform/Guardrails namespace)"
  value       = sort(keys(local.signals))
}

output "dashboard_name" {
  description = "Name of the dashboard. Empty unless create_dashboard is true."
  value       = length(aws_cloudwatch_dashboard.this) > 0 ? aws_cloudwatch_dashboard.this[0].dashboard_name : ""
}
