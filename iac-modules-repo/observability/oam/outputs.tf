output "sink_arn" {
  description = "sink mode: ARN of the sink. Give it to every source account's link (sink_arn). Empty in link mode."
  value       = local.is_sink ? aws_oam_sink.this[0].arn : ""
}

output "link_arn" {
  description = "link mode: ARN of this account's link. Empty in sink mode."
  value       = local.is_link ? aws_oam_link.this[0].arn : ""
}

output "prometheus_workspace_arn" {
  description = "ARN of the Managed Prometheus workspace. Empty unless enable_prometheus is true."
  value       = length(aws_prometheus_workspace.this) > 0 ? aws_prometheus_workspace.this[0].arn : ""
}
