output "distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution (e.g. d111111abcdef8.cloudfront.net)"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the CloudFront distribution (for alias records)"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "oac_id" {
  description = "ID of the Origin Access Control"
  value       = aws_cloudfront_origin_access_control.this.id
}

output "response_headers_policy_id" {
  description = "ID of the response headers policy (empty when disabled)"
  value       = var.enable_response_headers_policy ? aws_cloudfront_response_headers_policy.this[0].id : ""
}
