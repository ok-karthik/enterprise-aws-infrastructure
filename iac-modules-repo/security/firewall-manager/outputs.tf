output "waf_policy_id" {
  description = "ID of the FMS WAFv2 security policy"
  value       = aws_fms_policy.waf.id
}

output "waf_policy_arn" {
  description = "ARN of the FMS WAFv2 security policy"
  value       = aws_fms_policy.waf.policy_update_token
}

output "rate_limit_rule_group_arn" {
  description = "ARN of the rate-based WAFv2 rule group (empty when rate_limit is 0)"
  value       = var.rate_limit > 0 ? aws_wafv2_rule_group.rate_limit[0].arn : ""
}

output "sg_audit_policy_id" {
  description = "ID of the FMS security-group audit policy (empty when disabled)"
  value       = var.enable_sg_audit ? aws_fms_policy.sg_audit[0].id : ""
}

output "network_firewall_policy_id" {
  description = "ID of the FMS Network Firewall policy (empty when disabled)"
  value       = var.enable_network_firewall_policy ? aws_fms_policy.network_firewall[0].id : ""
}
