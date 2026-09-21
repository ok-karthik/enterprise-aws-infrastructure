output "external_analyzer_arn" {
  description = "ARN of the organization analyzer for external access"
  value       = aws_accessanalyzer_analyzer.external.arn
}

output "unused_analyzer_arn" {
  description = "ARN of the organization analyzer for unused access"
  value       = aws_accessanalyzer_analyzer.unused.arn
}
