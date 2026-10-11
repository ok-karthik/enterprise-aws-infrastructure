output "function_name" {
  description = "Name of the janitor Lambda"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the janitor Lambda"
  value       = aws_lambda_function.this.arn
}

output "log_group_name" {
  description = "Log group that holds the one-line JSON summary of each run"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "dry_run" {
  description = "Whether the janitor only reports"
  value       = var.dry_run
}
