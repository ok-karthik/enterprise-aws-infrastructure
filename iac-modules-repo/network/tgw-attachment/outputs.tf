output "attachment_id" {
  description = "ID of the VPC attachment (pending acceptance in network-hub until its accept step runs)"
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}
