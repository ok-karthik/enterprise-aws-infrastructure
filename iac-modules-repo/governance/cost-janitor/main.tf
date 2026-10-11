# Cost janitor (PLAN 9.5): a weekly Lambda that reports orphaned, billable resources in this account, and removes
# them only when dry_run = false. Report-only by default. Meant for dev, never prod.
#
# Safety, in two places: the code skips anything tagged keep=true, and the delete permissions exist in IAM only
# when dry_run = false (a separate policy) and then carry a condition that refuses resources tagged keep=true.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  tags = merge({ Service = "governance-cost-janitor", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.region
  account   = data.aws_caller_identity.current.account_id
}

# ------------------------------------------------------------------------------
# The Lambda
# ------------------------------------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.build/cost_janitor.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_158: "Repo-wide skip already covers this (known Checkov bug with a KMS key that is known-after-apply); a dedicated key for one small function's logs is not worth the cost here"
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda"

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
  name = "cost-janitor"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "WriteOwnLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
        },
        {
          Sid      = "ReadWhatCouldBeOrphaned"
          Effect   = "Allow"
          Action   = ["ec2:DescribeVolumes", "ec2:DescribeSnapshots", "ec2:DescribeImages", "ec2:DescribeAddresses", "logs:DescribeLogGroups"]
          Resource = "*"
        },
      ],
      var.alert_topic_arn == null ? [] : [{
        Sid      = "PublishSummary"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_topic_arn
      }],
    )
  })
}

# Only in act mode (dry_run = false). Resources tagged keep=true are refused by IAM as well as by the code.
resource "aws_iam_role_policy" "act" {
  count = var.dry_run ? 0 : 1

  name = "cost-janitor-act"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DeleteUnkeptVolumes"
        Effect    = "Allow"
        Action    = "ec2:DeleteVolume"
        Resource  = "arn:${local.partition}:ec2:${local.region}:${local.account}:volume/*"
        Condition = { StringNotEquals = { "aws:ResourceTag/keep" = "true" } }
      },
      {
        Sid       = "DeleteUnkeptSnapshots"
        Effect    = "Allow"
        Action    = "ec2:DeleteSnapshot"
        Resource  = "arn:${local.partition}:ec2:${local.region}::snapshot/*"
        Condition = { StringNotEquals = { "aws:ResourceTag/keep" = "true" } }
      },
      {
        Sid       = "ReleaseUnkeptElasticIps"
        Effect    = "Allow"
        Action    = "ec2:ReleaseAddress"
        Resource  = "arn:${local.partition}:ec2:${local.region}:${local.account}:elastic-ip/*"
        Condition = { StringNotEquals = { "aws:ResourceTag/keep" = "true" } }
      },
      {
        Sid      = "SetLogRetention"
        Effect   = "Allow"
        Action   = "logs:PutRetentionPolicy"
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:*"
      },
    ]
  })
}

resource "aws_lambda_function" "this" {
  #checkov:skip=CKV_AWS_116: "Not queue-driven; a failed weekly run shows in CloudWatch Logs and the next run repeats it, a DLQ adds nothing"
  #checkov:skip=CKV_AWS_173: "Environment variables are non-secret configuration (ages, flags, an SNS topic ARN); Lambda encrypts them with the AWS managed key by default"
  #checkov:skip=CKV_AWS_117: "Only calls AWS APIs (EC2, Logs, SNS), never a VPC resource; a VPC would need NAT or endpoints for no benefit"
  #checkov:skip=CKV_AWS_272: "Code signing is a bigger control (a signing profile and pipeline) than one small, reviewed function justifies right now"
  function_name                  = var.name
  reserved_concurrent_executions = 1 # one run at a time, so two runs never act on the same resources
  description                    = "Weekly report of orphaned EBS volumes, snapshots, Elastic IPs and log groups without retention (PLAN 9.5)"
  role                           = aws_iam_role.lambda.arn
  handler                        = "cost_janitor.handler"
  runtime                        = "python3.13"
  timeout                        = 300
  memory_size                    = 256

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DRY_RUN                    = tostring(var.dry_run)
      VOLUME_MIN_AGE_DAYS        = tostring(var.volume_min_age_days)
      SNAPSHOT_MIN_AGE_DAYS      = tostring(var.snapshot_min_age_days)
      DEFAULT_LOG_RETENTION_DAYS = tostring(var.default_log_retention_days)
      EXCLUDE_LOG_GROUP_PREFIXES = join(",", var.exclude_log_group_prefixes)
      ALERT_TOPIC_ARN            = var.alert_topic_arn == null ? "" : var.alert_topic_arn
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ------------------------------------------------------------------------------
# Schedule: EventBridge Scheduler invokes the Lambda
# ------------------------------------------------------------------------------
resource "aws_iam_role" "scheduler" {
  name = "${var.name}-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-cost-janitor"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.this.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  #checkov:skip=CKV_AWS_297: "The payload is an empty object; no sensitive data, so the default AWS-owned key is enough"
  name                         = "${var.name}-weekly"
  description                  = "Run the cost janitor"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})
  }
}
