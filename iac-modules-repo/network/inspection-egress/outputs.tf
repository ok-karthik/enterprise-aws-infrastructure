output "vpc_id" {
  description = "ID of the inspection/egress VPC"
  value       = aws_vpc.this.id
}

output "firewall_arn" {
  description = "ARN of the Network Firewall"
  value       = aws_networkfirewall_firewall.this.arn
}

output "nat_gateway_ids" {
  description = "AZ => NAT gateway ID"
  value       = { for az, ng in aws_nat_gateway.this : az => ng.id }
}

output "tgw_attachment_id" {
  description = "ID of this VPC's own transit gateway attachment"
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}
