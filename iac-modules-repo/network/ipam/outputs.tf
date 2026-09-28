output "ipam_id" {
  description = "ID of the org-wide IPAM"
  value       = aws_vpc_ipam.this.id
}

output "top_level_pool_id" {
  description = "ID of the top-level pool"
  value       = aws_vpc_ipam_pool.top_level.id
}

output "regional_pool_ids" {
  description = "Region => regional pool ID"
  value       = { for k, p in aws_vpc_ipam_pool.regional : k => p.id }
}

output "env_pool_ids" {
  description = "\"<region>/<env>\" => env pool ID (env is prod or nonprod), for network/vpc's ipv4_ipam_pool_id input"
  value       = { for k, p in aws_vpc_ipam_pool.env : k => p.id }
}

output "resource_share_arn" {
  description = "ARN of the RAM share the regional pools are shared through"
  value       = aws_ram_resource_share.pools.arn
}
