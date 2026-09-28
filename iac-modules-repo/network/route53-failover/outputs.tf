output "health_check_id" {
  description = "ID of the primary's health check (alarm on it in CloudWatch, us-east-1)"
  value       = aws_route53_health_check.primary.id
}

output "record_fqdn" {
  description = "Failover record name"
  value       = aws_route53_record.primary.fqdn
}
