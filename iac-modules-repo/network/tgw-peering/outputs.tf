output "peering_attachment_id" {
  description = "ID of the peering attachment: the one this requester created, or the one this accepter accepted. The accepter's Terragrunt unit reads the requester's value."
  value       = var.role == "requester" ? aws_ec2_transit_gateway_peering_attachment.this[0].id : aws_ec2_transit_gateway_peering_attachment_accepter.this[0].id
}
