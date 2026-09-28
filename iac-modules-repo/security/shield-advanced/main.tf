# Shield Advanced (PLAN 6.4): optional DDoS protection for prod-tier resources.
# Applied per account (or centrally from the FMS admin when FMS Shield policy is used).
#
# ⚠️  COST WARNING: Shield Advanced costs $3,000/month per organization. See FINOPS.md.
# The subscription covers ALL accounts in the organization once enabled in ANY account.
# Only enable this when the business case justifies the cost (>$3k/month in potential DDoS damage).

locals {
  tags = merge({ Service = "security-shield-advanced", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

# ------------------------------------------------------------------------------
# Shield Advanced subscription
# ------------------------------------------------------------------------------
resource "aws_shield_subscription" "this" {
  count = var.enabled ? 1 : 0

  auto_renew = "ENABLED"
}

# ------------------------------------------------------------------------------
# Protections: one per resource
# ------------------------------------------------------------------------------
resource "aws_shield_protection" "this" {
  for_each = var.enabled ? var.protected_resources : {}

  name         = each.key
  resource_arn = each.value

  tags = local.tags

  depends_on = [aws_shield_subscription.this]
}

# ------------------------------------------------------------------------------
# Proactive engagement contacts
# ------------------------------------------------------------------------------
resource "aws_shield_proactive_engagement" "this" {
  count = var.enabled && var.enable_proactive_engagement ? 1 : 0

  enabled = true

  dynamic "emergency_contact" {
    for_each = var.proactive_engagement_contacts
    content {
      email_address = emergency_contact.value.email_address
      phone_number  = emergency_contact.value.phone_number
      contact_notes = emergency_contact.value.note
    }
  }

  depends_on = [aws_shield_subscription.this]
}

# ------------------------------------------------------------------------------
# DRT (Shield Response Team) access
# ------------------------------------------------------------------------------
resource "aws_shield_drt_access_role_arn_association" "this" {
  count = var.enabled && var.drt_access_role_arn != "" ? 1 : 0

  role_arn = var.drt_access_role_arn

  depends_on = [aws_shield_subscription.this]
}

# ------------------------------------------------------------------------------
# Application-layer auto-remediation per protection
# (Shield automatically creates WAF rate-based rules when it detects a DDoS event)
# ------------------------------------------------------------------------------
resource "aws_shield_application_layer_automatic_response" "this" {
  for_each = var.enabled && var.enable_auto_remediation ? {
    for k, v in var.protected_resources : k => v
    if can(regex("(cloudfront|elasticloadbalancing)", v))
  } : {}

  resource_arn = each.value
  action       = var.auto_remediation_action == "BLOCK" ? "BLOCK" : "COUNT"

  depends_on = [aws_shield_protection.this]
}
