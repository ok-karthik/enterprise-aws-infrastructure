# Auto-remediation for open SSH/RDP security group rules (PLAN 4.9), applied in security-tooling.
#
# Cross-account event delivery: EventBridge only sees events for API activity made in its OWN account, even
# for an organization CloudTrail (security/org-cloudtrail already covers the audit trail itself; this is a
# separate, well-known EventBridge limitation). So a member account's AuthorizeSecurityGroupIngress event
# cannot be matched by a rule on security-tooling's default bus directly. The standard fix: a CUSTOM event
# bus here, with a resource policy that lets any account in the organization PutEvents on it, and a small
# EventBridge rule in EACH MEMBER ACCOUNT (added by governance/account-baseline) that forwards the same event
# to this bus. This module owns the central bus, the Lambda, and the rule that reacts to forwarded events;
# governance/account-baseline owns the per-account forwarding rule and the security-remediation role the
# Lambda assumes back into that account.
#
# NOT built here: the second trigger PLAN 4.9 asks for (the matching Config rule, e.g. restricted-ssh). PLAN 4.3
# (the org Config recorder and conformance packs) is out of scope for this PR, so there is no Config rule to
# react to yet. Add it the same way once 4.3 exists: a rule on this bus for the Config compliance-change event,
# forwarded from each member account.

data "aws_partition" "current" {}

locals {
  tags = merge({ Service = "security-auto-remediation", ManagedBy = "Terragrunt-Wrapper" }, var.tags)
}

# ------------------------------------------------------------------------------
# Central event bus: member accounts forward their AuthorizeSecurityGroupIngress event here.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_event_bus" "central" {
  name = "auto-remediation"

  tags = local.tags
}

resource "aws_cloudwatch_event_bus_policy" "central" {
  event_bus_name = aws_cloudwatch_event_bus.central.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrganizationAccountsToForward"
      Effect    = "Allow"
      Principal = "*"
      Action    = "events:PutEvents"
      Resource  = aws_cloudwatch_event_bus.central.arn
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.organization_id } }
    }]
  })
}

resource "aws_cloudwatch_event_rule" "authorize_security_group_ingress" {
  name           = "forwarded-authorize-security-group-ingress"
  description    = "A member account opened a security group ingress rule (forwarded from that account's own bus)"
  event_bus_name = aws_cloudwatch_event_bus.central.name

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress"]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.authorize_security_group_ingress.name
  event_bus_name = aws_cloudwatch_event_bus.central.name
  arn            = aws_lambda_function.remediate_open_ssh.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeToInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_open_ssh.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.authorize_security_group_ingress.arn
}

# ------------------------------------------------------------------------------
# The Lambda
# ------------------------------------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/remediate_open_ssh.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_158: "Repo-wide skip already covers this (known Checkov bug with a KMS key that is known-after-apply); a dedicated key for one small function's logs is not worth the cost here"
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

locals {
  function_name = "auto-remediate-open-ssh"
}

resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowLambdaToAssume"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "auto-remediation"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        # Every member account's security-remediation role, by name, in every account (the account id is not
        # known here): scoped to that one role name, not to all roles.
        Sid      = "AssumeTheRemediationRoleInAnyMemberAccount"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:${data.aws_partition.current.partition}:iam::*:role/${var.remediation_role_name}"
      },
      {
        Sid      = "PublishRemediationSummaries"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      },
    ]
  })
}

resource "aws_lambda_function" "remediate_open_ssh" {
  #checkov:skip=CKV_AWS_116: "Not a queue-driven function; failures are visible in CloudWatch Logs and the source EventBridge rule, DLQ is a follow-up if false negatives show up in practice"
  #checkov:skip=CKV_AWS_173: "Environment variables here are non-secret configuration (a role name, an SNS topic ARN); Lambda encrypts them with the AWS managed key by default"
  #checkov:skip=CKV_AWS_117: "This function only calls AWS APIs (STS, EC2, SNS) across accounts, never a VPC resource; putting it in a VPC would need NAT/VPC endpoints and risks the < 30s remediation target"
  #checkov:skip=CKV_AWS_272: "Code signing is a bigger control (a signing profile and pipeline) than one small, reviewed function justifies right now"
  function_name                  = local.function_name
  reserved_concurrent_executions = 5 # caps duplicate/thrashing remediations without a separate skip
  description                    = "Removes 0.0.0.0/0 / ::/0 ingress on port 22 or 3389 (PLAN 4.9)"
  role                           = aws_iam_role.lambda.arn
  handler                        = "remediate_open_ssh.handler"
  runtime                        = "python3.13"
  timeout                        = var.lambda_timeout_seconds
  memory_size                    = 128

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      REMEDIATION_ROLE_NAME = var.remediation_role_name
      ALERT_TOPIC_ARN       = var.alert_topic_arn
      AWS_PARTITION         = data.aws_partition.current.partition
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.lambda]
}
