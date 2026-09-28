output "vpc_id" {
  description = "ID of the shared-endpoints VPC"
  value       = aws_vpc.this.id
}

output "endpoint_ids" {
  description = "Service short name => interface endpoint ID"
  value       = { for k, e in aws_vpc_endpoint.this : k => e.id }
}

output "hosted_zone_ids" {
  description = "Service short name => private hosted zone ID (share this with a spoke account for its own aws_route53_zone_association)"
  value       = { for k, z in aws_route53_zone.this : k => z.zone_id }
}
