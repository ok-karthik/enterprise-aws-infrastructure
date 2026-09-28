variable "admin_account_id" {
  description = "12-digit ID of the FMS administrator (security-tooling). Delegation itself is done by governance/organization (delegated_administrators[\"fms.amazonaws.com\"])."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.admin_account_id)) && !startswith(var.admin_account_id, "00000000")
    error_message = "admin_account_id must be a real 12-digit account id."
  }
}

# ---------------------------------------------------------------------------
# WAFv2 policy
# ---------------------------------------------------------------------------

variable "waf_policy_name" {
  description = "Name of the FMS WAFv2 security policy."
  type        = string
  default     = "platform-waf-policy"
}

variable "waf_target_ou_ids" {
  description = "OU IDs whose accounts receive the WAFv2 policy. Use the Workloads OU (or both Workloads + Infrastructure)."
  type        = list(string)

  validation {
    condition     = length(var.waf_target_ou_ids) > 0
    error_message = "waf_target_ou_ids must not be empty."
  }
}

variable "waf_resource_types" {
  description = "Resource types protected by the WAFv2 policy."
  type        = list(string)
  default     = ["AWS::ElasticLoadBalancingV2::LoadBalancer", "AWS::ApiGateway::Stage", "AWS::CloudFront::Distribution"]

  validation {
    condition     = length(var.waf_resource_types) > 0
    error_message = "waf_resource_types must not be empty."
  }
}

variable "waf_default_action" {
  description = "Default action for the managed web ACL. ALLOW lets through traffic that matches no rule; COUNT logs everything without blocking."
  type        = string
  default     = "ALLOW"

  validation {
    condition     = contains(["ALLOW", "COUNT"], var.waf_default_action)
    error_message = "waf_default_action must be ALLOW or COUNT."
  }
}

variable "rate_limit" {
  description = "Requests per 5 minutes per IP before the rate-based rule blocks. 0 disables the rate-based rule."
  type        = number
  default     = 2000

  validation {
    condition     = var.rate_limit == 0 || (var.rate_limit >= 100 && var.rate_limit <= 2000000000)
    error_message = "rate_limit must be 0 (disabled) or between 100 and 2 000 000 000."
  }
}

variable "enable_bot_control" {
  description = "Enable the AWS Managed Bot Control rule group. Recommended for prod (count mode by default)."
  type        = bool
  default     = false
}

variable "bot_control_action" {
  description = "Override action for Bot Control rules: COUNT (observe first) or BLOCK. Only used when enable_bot_control is true."
  type        = string
  default     = "COUNT"

  validation {
    condition     = contains(["COUNT", "BLOCK"], var.bot_control_action)
    error_message = "bot_control_action must be COUNT or BLOCK."
  }
}

# ---------------------------------------------------------------------------
# Security-group audit policy
# ---------------------------------------------------------------------------

variable "enable_sg_audit" {
  description = "Enable the FMS security-group audit policy that flags overly open SGs."
  type        = bool
  default     = true
}

variable "sg_audit_policy_name" {
  description = "Name of the security-group audit policy."
  type        = string
  default     = "platform-sg-audit-policy"
}

variable "sg_audit_target_ou_ids" {
  description = "OU IDs audited by the SG policy. Defaults to the same as waf_target_ou_ids if empty."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Network Firewall policy (requires Phase 5.3 inspection-egress)
# ---------------------------------------------------------------------------

variable "enable_network_firewall_policy" {
  description = "Enable the FMS Network Firewall policy. Only set this to true when Phase 5.3 (inspection-egress) is deployed."
  type        = bool
  default     = false
}

variable "nfw_policy_name" {
  description = "Name of the FMS Network Firewall policy."
  type        = string
  default     = "platform-network-firewall-policy"
}

variable "nfw_target_ou_ids" {
  description = "OU IDs that receive the Network Firewall policy."
  type        = list(string)
  default     = []
}

variable "nfw_stateful_rule_group_arns" {
  description = "ARNs of Network Firewall stateful rule groups to reference in the FMS policy."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------

variable "exclude_account_ids" {
  description = "Account IDs to exclude from all FMS policies (management account, sandbox accounts, etc.)."
  type        = list(string)
  default     = []
}

variable "remediation_enabled" {
  description = "Whether FMS auto-remediates non-compliant resources. Start with false (audit mode), then enable after reviewing findings."
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
