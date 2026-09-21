variable "organization_id" {
  description = "ID of the AWS Organization (o-xxxxxxxxxx). Every delivery bucket policy only lets AWS services write when aws:SourceOrgID is this organization."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && !can(regex("^o-0+$", var.organization_id))
    error_message = "organization_id must be a real organization id (o-...), not the 0000 placeholder."
  }
}

variable "management_account_id" {
  description = "12-digit ID of the management account: the organization trail is created there and writes to AWSLogs/<this id>/."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id)) && !startswith(var.management_account_id, "00000000")
    error_message = "management_account_id must be a real 12-digit account id (a 000000000xxx registry placeholder is refused)."
  }
}

variable "trail_name" {
  description = "Name of the organization trail (the org-cloudtrail module). The CloudTrail bucket policy only accepts writes from this trail."
  type        = string
  default     = "platform-org-trail"
}

variable "trail_home_region" {
  description = "Home region of the organization trail. Empty means the region this module is applied in."
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix of every bucket. Bucket names are <prefix>-<log type>-<account id>-<region> (the WAF bucket is aws-waf-logs-<prefix>-...): the org-cloudtrail leaf builds the same name, so they are a contract."
  type        = string
  default     = "platform"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "name_prefix must be 2-21 lowercase letters, digits or hyphens."
  }
}

variable "enabled_log_types" {
  description = "Which log buckets to create."
  type        = list(string)
  default     = ["cloudtrail", "config", "vpc_flow_logs", "waf", "alb_access", "cloudfront_access", "state_access"]

  validation {
    condition     = length(var.enabled_log_types) > 0 && alltrue([for t in var.enabled_log_types : contains(["cloudtrail", "config", "vpc_flow_logs", "waf", "alb_access", "cloudfront_access", "state_access"], t)])
    error_message = "enabled_log_types may only contain cloudtrail, config, vpc_flow_logs, waf, alb_access, cloudfront_access, state_access."
  }
}

variable "retention_days" {
  description = <<-EOT
    Object Lock retention in days per log type. Objects cannot be deleted or overwritten before this, not even by
    the account root, when object_lock_mode is COMPLIANCE. CloudTrail and Config default to 400 days (SOC 2 / ISO 27001
    evidence, see docs/COMPLIANCE.md); the rest to 90. Types missing from the map use 90.
  EOT
  type        = map(number)
  default = {
    cloudtrail = 400
    config     = 400
  }

  validation {
    condition     = alltrue([for t, d in var.retention_days : d >= 1 && d <= 3650 && floor(d) == d])
    error_message = "Every retention must be a whole number of days between 1 and 3650."
  }
}

variable "object_lock_mode" {
  description = "COMPLIANCE (nobody can shorten or remove the lock, the audit setting) or GOVERNANCE (a privileged principal can bypass it). COMPLIANCE cannot be undone: objects stay, and are billed, until retention ends."
  type        = string
  default     = "COMPLIANCE"

  validation {
    condition     = contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be COMPLIANCE or GOVERNANCE."
  }
}

variable "glacier_transition_days" {
  description = "Move objects to Glacier after this many days. A log type whose retention is not longer than this is not transitioned."
  type        = number
  default     = 90

  validation {
    condition     = var.glacier_transition_days >= 30
    error_message = "glacier_transition_days must be at least 30."
  }
}

variable "expire_after_retention_days" {
  description = "Delete objects (and old versions) this many days after the Object Lock retention ends."
  type        = number
  default     = 30

  validation {
    condition     = var.expire_after_retention_days >= 1
    error_message = "expire_after_retention_days must be at least 1."
  }
}

variable "alb_log_delivery_principal_arns" {
  description = <<-EOT
    IAM principals that deliver ALB access logs. Regions opened before August 2022 use a regional ELB account (the default is the
    one for eu-central-1). For a newer region set this to [] and the policy uses the service principal
    logdelivery.elasticloadbalancing.amazonaws.com instead. Check the current AWS documentation for your region.
  EOT
  type        = list(string)
  default     = ["arn:aws:iam::054676820928:root"]
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a scheduled deletion of the KMS key."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
