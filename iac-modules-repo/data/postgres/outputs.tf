output "db_identifier" {
  description = "Generated RDS identifier, including the uniqueness suffix"
  value       = aws_db_instance.this.identifier
}

output "db_endpoint" {
  description = "Connection endpoint for the RDS instance"
  value       = aws_db_instance.this.endpoint
}

output "master_secret_arn" {
  description = "Secrets Manager ARN holding the master user password"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
