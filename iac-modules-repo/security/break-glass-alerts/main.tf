# Alerts for break-glass access: an EventBridge rule per sign-in path, an encrypted SNS topic and email
# subscriptions. Regional (EventBridge sees the events of its own region); applied in every account, and
# with the portal rule also in the management account. See docs/BREAK_GLASS.md.
#
# CloudTrail management events must be on for EventBridge to see these events (they are by default).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  topic_name = "${var.name_prefix}-alerts"
  role_glob  = "*AWSReservedSSO_${var.permission_set_name}_*"

  tags = merge({ Service = "security-break-glass-alerts", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  # One rule per way of signing in. Patterns use ARN strings, not resource references, so the key
  # and topic policies can name the rules without a dependency cycle.
  rules = merge(
    {
      # Console or CLI use of the role in THIS account: the STS call that hands out the session.
      saml_assume_role = {
        description = "${var.permission_set_name} session started in this account (AssumeRoleWithSAML)"
        pattern = {
          "detail-type" = ["AWS API Call via CloudTrail"]
          detail = {
            eventSource       = ["sts.amazonaws.com"]
            eventName         = ["AssumeRoleWithSAML"]
            requestParameters = { roleArn = [{ wildcard = local.role_glob }] }
          }
        }
      }
      # Console sign-in as the role.
      console_login = {
        description = "${var.permission_set_name} console sign-in in this account"
        pattern = {
          "detail-type" = ["AWS Console Sign In via CloudTrail"]
          detail        = { userIdentity = { arn = [{ wildcard = local.role_glob }] } }
        }
      }
    },
    var.enable_sso_portal_rule ? {
      # The Identity Center portal, logged in the management account: shows CLI sign-ins too.
      sso_portal = {
        description = "${var.permission_set_name} requested through the IAM Identity Center portal"
        pattern = {
          "detail-type" = ["AWS API Call via CloudTrail"]
          detail = {
            eventSource = ["sso.amazonaws.com"]
            eventName   = ["Federate", "GetRoleCredentials"]
            requestParameters = {
              # The field name differs per event (role_name for Federate, roleName for GetRoleCredentials).
              roleName = [var.permission_set_name]
            }
          }
        }
      }
    } : {}
  )

  rule_arns = [for name, _ in local.rules : "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${var.name_prefix}-${replace(name, "_", "-")}"]
}

# ------------------------------------------------------------------------------
# Encrypted topic (the org's encryption rule requires a KMS key on every SNS topic)
# ------------------------------------------------------------------------------
resource "aws_kms_key" "alerts" {
  description             = "Encrypts the break-glass alert topic"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIamPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # EventBridge has to encrypt the message it publishes to the topic.
        Sid       = "AllowEventBridgeToPublishEncrypted"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = { ArnEquals = { "aws:SourceArn" = local.rule_arns } }
      },
    ]
  })

  tags = local.tags
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/${var.name_prefix}-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = local.topic_name
  display_name      = "Break-glass alerts"
  kms_master_key_id = aws_kms_key.alerts.arn

  tags = local.tags
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowBreakGlassRulesToPublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = { ArnEquals = { "aws:SourceArn" = local.rule_arns } }
    }]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ------------------------------------------------------------------------------
# Rules and targets
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name          = "${var.name_prefix}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  event_pattern = jsonencode(each.value.pattern)

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "sns" {
  for_each = local.rules

  rule = aws_cloudwatch_event_rule.this[each.key].name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      time    = "$.time"
      account = "$.account"
      region  = "$.region"
      who     = "$.detail.userIdentity.arn"
      ip      = "$.detail.sourceIPAddress"
      event   = "$.detail.eventName"
    }
    input_template = "\"BREAK-GLASS: <event> in account <account> (<region>) by <who> from <ip> at <time>. If nobody asked for this access, treat it as an incident (docs/BREAK_GLASS.md).\""
  }
}
