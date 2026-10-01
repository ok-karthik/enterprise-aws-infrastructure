output "recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.this.name
}

output "delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.this.name
}

output "aggregator_arn" {
  description = "ARN of the organization configuration aggregator (null outside primary region)"
  value       = try(aws_config_configuration_aggregator.organization[0].arn, null)
}

output "conformance_pack_names" {
  description = "List of enabled organization conformance pack names"
  value = compact([
    try(aws_config_organization_conformance_pack.cis[0].name, ""),
    try(aws_config_organization_conformance_pack.nist[0].name, ""),
    try(aws_config_organization_conformance_pack.soc2[0].name, "")
  ])
}
