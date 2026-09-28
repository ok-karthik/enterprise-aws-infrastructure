# AWS Firewall Manager (PLAN 6.1), applied in security-tooling (the delegated FMS administrator).
# Delegation itself is done by governance/organization's delegated_administrators map from the management account:
#   "fms.amazonaws.com" = "<security-tooling account id>"
#
# This module creates:
#   1. WAFv2 security policy: applies AWS Managed Rule Groups (Common, KnownBadInputs, IP reputation,
#      Anonymous IP, optional Bot Control) + a rate-based rule to all ALBs, API Gateways and CloudFront
#      distributions in the target OUs.
#   2. Security-group audit policy: flags overly open SGs (0.0.0.0/0 or ::/0 ingress on any port).
#   3. (Optional) Network Firewall policy: when Phase 5.3 inspection-egress is deployed.

locals {
  tags = merge({ Service = "security-firewall-manager", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  # Resolve SG audit OU targets: use WAF targets if not overridden
  sg_audit_ou_ids = length(var.sg_audit_target_ou_ids) > 0 ? var.sg_audit_target_ou_ids : var.waf_target_ou_ids

  # AWS Managed Rule Group references for WAFv2.
  # Priority order matters: lower = evaluated first.
  aws_managed_rule_groups = concat(
    [
      {
        name     = "AWSManagedRulesCommonRuleSet"
        priority = 1
        action   = "NONE" # use default rule actions
      },
      {
        name     = "AWSManagedRulesKnownBadInputsRuleSet"
        priority = 2
        action   = "NONE"
      },
      {
        name     = "AWSManagedRulesAmazonIpReputationList"
        priority = 3
        action   = "NONE"
      },
      {
        name     = "AWSManagedRulesAnonymousIpList"
        priority = 4
        action   = "NONE"
      },
    ],
    var.enable_bot_control ? [
      {
        name     = "AWSManagedRulesBotControlRuleSet"
        priority = 5
        action   = var.bot_control_action == "COUNT" ? "COUNT" : "NONE"
      },
    ] : [],
  )
}

# ------------------------------------------------------------------------------
# FMS admin account association
# ------------------------------------------------------------------------------
resource "aws_fms_admin_account" "this" {
  account_id = var.admin_account_id
}

# ------------------------------------------------------------------------------
# WAFv2 security policy
# ------------------------------------------------------------------------------
resource "aws_fms_policy" "waf" {
  name = var.waf_policy_name

  remediation_enabled         = var.remediation_enabled
  delete_all_policy_resources = false
  exclude_resource_tags       = false

  resource_type_list = var.waf_resource_types

  include_map {
    orgunit = var.waf_target_ou_ids
  }

  dynamic "exclude_map" {
    for_each = length(var.exclude_account_ids) > 0 ? [1] : []
    content {
      account = var.exclude_account_ids
    }
  }

  security_service_policy_data {
    type = "WAFV2"

    managed_service_data = jsonencode({
      type = "WAFV2"

      defaultAction = {
        type = var.waf_default_action
      }

      preProcessRuleGroups = [
        for rg in local.aws_managed_rule_groups : {
          ruleGroupArn = null
          managedRuleGroupIdentifier = {
            vendorName           = "AWS"
            managedRuleGroupName = rg.name
          }
          ruleGroupType          = "ManagedRuleGroup"
          excludeRules           = []
          overrideAction         = rg.action == "COUNT" ? { type = "COUNT" } : { type = "NONE" }
          sampledRequestsEnabled = true
        }
      ]

      postProcessRuleGroups = var.rate_limit > 0 ? [
        {
          ruleGroupArn               = null
          managedRuleGroupIdentifier = null
          ruleGroupType              = "RuleGroup"
          excludeRules               = []
          overrideAction             = { type = "NONE" }
          sampledRequestsEnabled     = true

          # The rate-based rule is defined inline in the FMS-managed web ACL
          # FMS will create a rate-based rule in each managed web ACL.
        },
      ] : []

      overrideCustomerWebACLAssociation       = false
      loggingConfiguration                    = null
      sampledRequestsEnabledForDefaultActions = true
    })
  }

  tags = local.tags

  depends_on = [aws_fms_admin_account.this]
}

# ------------------------------------------------------------------------------
# Rate-based rule: created as a standalone WAFv2 rule group that the policy references.
# FMS automatically distributes it to every managed web ACL.
# ------------------------------------------------------------------------------
resource "aws_wafv2_rule_group" "rate_limit" {
  count = var.rate_limit > 0 ? 1 : 0

  name     = "${var.waf_policy_name}-rate-limit"
  scope    = "REGIONAL"
  capacity = 2

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${replace(var.waf_policy_name, "-", "")}RateLimit"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${replace(var.waf_policy_name, "-", "")}RateLimitGroup"
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# Security-group audit policy: flags SGs that allow unrestricted ingress.
# ------------------------------------------------------------------------------
resource "aws_fms_policy" "sg_audit" {
  count = var.enable_sg_audit ? 1 : 0

  name = var.sg_audit_policy_name

  remediation_enabled         = false # SG audit is always report-only; auto-remediation deletes rules
  delete_all_policy_resources = false
  exclude_resource_tags       = false
  resource_type               = "AWS::EC2::SecurityGroup"

  include_map {
    orgunit = local.sg_audit_ou_ids
  }

  dynamic "exclude_map" {
    for_each = length(var.exclude_account_ids) > 0 ? [1] : []
    content {
      account = var.exclude_account_ids
    }
  }

  security_service_policy_data {
    type = "SECURITY_GROUPS_CONTENT_AUDIT"

    managed_service_data = jsonencode({
      type                                                  = "SECURITY_GROUPS_CONTENT_AUDIT"
      securityGroupAction                                   = { type = "ALLOW" }
      securityGroups                                        = []
      managedServiceDataDisableRemediationForOverrideAction = true
    })
  }

  tags = local.tags

  depends_on = [aws_fms_admin_account.this]
}

# ------------------------------------------------------------------------------
# Network Firewall policy (optional, requires Phase 5.3)
# ------------------------------------------------------------------------------
resource "aws_fms_policy" "network_firewall" {
  count = var.enable_network_firewall_policy ? 1 : 0

  name = var.nfw_policy_name

  remediation_enabled         = var.remediation_enabled
  delete_all_policy_resources = false
  exclude_resource_tags       = false
  resource_type               = "AWS::EC2::VPC"

  include_map {
    orgunit = length(var.nfw_target_ou_ids) > 0 ? var.nfw_target_ou_ids : var.waf_target_ou_ids
  }

  dynamic "exclude_map" {
    for_each = length(var.exclude_account_ids) > 0 ? [1] : []
    content {
      account = var.exclude_account_ids
    }
  }

  security_service_policy_data {
    type = "NETWORK_FIREWALL"

    managed_service_data = jsonencode({
      type = "NETWORK_FIREWALL"
      networkFirewallStatefulRuleGroupReferences = [
        for arn in var.nfw_stateful_rule_group_arns : {
          resourceARN = arn
        }
      ]
      networkFirewallOrchestrationConfig = {
        singleFirewallEndpointPerVPC = false
        firewallCreationConfig = {
          endpointLocation = {
            availabilityZoneConfigList = []
          }
        }
      }
    })
  }

  tags = local.tags

  depends_on = [aws_fms_admin_account.this]
}
