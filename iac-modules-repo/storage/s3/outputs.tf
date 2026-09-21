output "bucket_name" {
  description = "Generated bucket name, including the uniqueness suffix"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN, for IAM policies written elsewhere"
  value       = aws_s3_bucket.this.arn
}
