output "vpc_id" {
  description = "ID of this module's own VPC"
  value       = aws_vpc.this.id
}

output "inbound_endpoint_id" {
  description = "ID of the inbound resolver endpoint (on-prem queries the platform through this)"
  value       = aws_route53_resolver_endpoint.inbound.id
}

output "outbound_endpoint_id" {
  description = "ID of the outbound resolver endpoint (the platform forwards on-prem-domain queries through this)"
  value       = aws_route53_resolver_endpoint.outbound.id
}

output "resolver_rule_ids" {
  description = "domain_name => resolver rule ID"
  value       = { for k, r in aws_route53_resolver_rule.forwarding : k => r.id }
}

output "resolver_share_arn" {
  description = "ARN of the RAM share the forwarding rules and query log config are shared through"
  value       = aws_ram_resource_share.this.arn
}

output "root_zone_id" {
  description = "ID of the public root zone, or null when root_domain is empty"
  value       = try(aws_route53_zone.root[0].zone_id, null)
}

output "delegated_zone_ids" {
  description = "Workload account name => its delegated subdomain's public hosted zone ID"
  value       = { for k, z in aws_route53_zone.delegated : k => z.zone_id }
}
