variable "trail_name" {
  description = "Name of the organization trail. Must match the name the log-archive bucket policy trusts (security/log-archive var.trail_name)."
  type        = string
  default     = "platform-org-trail"
}

variable "log_archive_bucket_name" {
  description = "Name of the CloudTrail bucket in the log-archive account (security/log-archive output bucket_names[\"cloudtrail\"]; the two modules share the naming contract, so this can be computed without reading that module's state)."
  type        = string

  validation {
    condition     = length(var.log_archive_bucket_name) > 0
    error_message = "log_archive_bucket_name must not be empty."
  }
}

variable "s3_key_prefix" {
  description = "Key prefix inside the log-archive bucket. Empty means none."
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "ARN of the log-archive KMS key (security/log-archive output kms_key_arn) that encrypts the trail's log files."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account id>:key/...)."
  }
}

variable "confidential_s3_bucket_arns" {
  description = <<-EOT
    S3 bucket ARNs tagged DataClassification=confidential (docs/DISCOVERY_CONTRACT.md, account-baseline's general/confidential
    key split): the trail logs S3 data events (object-level reads and writes) for these buckets. Terraform cannot discover
    tagged buckets across accounts by itself, so this is populated by hand or by a future automated collector. Empty means
    only management events are logged (the trail's default), which is also what a trail with no advanced_event_selector does.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.confidential_s3_bucket_arns : can(regex("^arn:aws[a-zA-Z-]*:s3:::", arn))])
    error_message = "Every entry must be an S3 bucket ARN (arn:aws:s3:::<bucket>)."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Retention (days) of the /aws/cloudtrail/<trail name> CloudWatch Logs group. Must be one of the values CloudWatch Logs accepts."
  type        = number
  default     = 400

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, 0], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a value CloudWatch Logs accepts (see the aws_cloudwatch_log_group documentation); 0 means never expire."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a scheduled deletion of the CloudWatch Logs / SNS KMS key (not the log-archive key, which this module does not create)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "enable_cloudtrail_lake" {
  description = "Also create a CloudTrail Lake organization event data store, for SQL queries over trail events without exporting to S3/Athena."
  type        = bool
  default     = false
}

variable "cloudtrail_lake_retention_days" {
  description = "Retention (days) of the CloudTrail Lake event data store, when enabled."
  type        = number
  default     = 400

  validation {
    condition     = var.cloudtrail_lake_retention_days >= 7 && var.cloudtrail_lake_retention_days <= 3653
    error_message = "cloudtrail_lake_retention_days must be between 7 and 3653 (AWS CloudTrail Lake limits)."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
