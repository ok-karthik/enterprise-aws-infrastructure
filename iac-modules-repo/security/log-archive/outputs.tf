output "bucket_names" {
  description = "Log type => bucket name"
  value       = { for t, b in local.buckets : t => b.name }
}

output "bucket_arns" {
  description = "Log type => bucket ARN"
  value       = { for t, b in aws_s3_bucket.this : t => b.arn }
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the logs (the org trail is given this ARN)"
  value       = aws_kms_key.logs.arn
}

output "kms_key_id" {
  description = "ID of the KMS key that encrypts the logs"
  value       = aws_kms_key.logs.key_id
}
