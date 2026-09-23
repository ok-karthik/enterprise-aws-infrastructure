output "transit_gateway_id" {
  description = "ID of the transit gateway"
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "ARN of the transit gateway"
  value       = aws_ec2_transit_gateway.this.arn
}

output "route_table_ids" {
  description = "Route table name (prod, nonprod, shared, inspection) => its ID"
  value       = { for k, rt in aws_ec2_transit_gateway_route_table.this : k => rt.id }
}

output "resource_share_arn" {
  description = "ARN of the RAM share the transit gateway itself is shared through"
  value       = aws_ram_resource_share.this.arn
}

output "peering_attachment_id" {
  description = "ID of the peering attachment this region created as requester, or null (used by the other region's accepter, via a Terragrunt dependency)"
  value       = try(aws_ec2_transit_gateway_peering_attachment.this[0].id, null)
}

output "accepted_vpc_attachment_ids" {
  description = "IDs of the spoke VPC attachments this leaf discovered and accepted"
  value       = var.accept_vpc_attachments ? data.aws_ec2_transit_gateway_vpc_attachments.pending[0].ids : []
}
