variable "name_prefix" {
  description = "Prefix for alarm and dashboard names"
  type        = string
  default     = "platform-guardrails"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name_prefix))
    error_message = "name_prefix must be 3-41 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "create_alarms" {
  description = "Create the metric filters and alarms. True where the organization trail's CloudWatch log group lives (the management account); false in an account that only shows the dashboard."
  type        = bool
  default     = true
}

variable "log_group_name" {
  description = "CloudWatch log group that receives the organization CloudTrail (the cloudwatch_log_group_name output of security/org-cloudtrail). Required when create_alarms is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_alarms || var.log_group_name != ""
    error_message = "log_group_name is required when create_alarms is true."
  }
}

variable "alarm_topic_arn" {
  description = "SNS topic that receives the alarms (for example the security-alerts topic). Empty = alarms exist but notify nobody."
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_topic_arn == "" || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:", var.alarm_topic_arn))
    error_message = "alarm_topic_arn must be empty or an SNS topic ARN."
  }
}

variable "create_dashboard" {
  description = "Create the one dashboard 'guardrails are working'. Normally applied in the observability account."
  type        = bool
  default     = false
}

variable "metrics_account_id" {
  description = "Dashboard only: the account that owns the metrics (the one with create_alarms = true). Read through cross-account observability (observability/oam). Empty = this account."
  type        = string
  default     = ""

  validation {
    condition     = var.metrics_account_id == "" || can(regex("^[0-9]{12}$", var.metrics_account_id))
    error_message = "metrics_account_id must be empty or a 12-digit account ID."
  }
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
