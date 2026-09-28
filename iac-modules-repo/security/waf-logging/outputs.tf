output "firehose_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream for WAF logs"
  value       = aws_kinesis_firehose_delivery_stream.waf_logs.arn
}

output "firehose_name" {
  description = "Name of the Firehose delivery stream (starts with aws-waf-logs-)"
  value       = aws_kinesis_firehose_delivery_stream.waf_logs.name
}

output "firehose_role_arn" {
  description = "ARN of the IAM role used by Firehose"
  value       = aws_iam_role.firehose.arn
}
