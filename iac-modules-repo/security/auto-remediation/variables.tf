variable "organization_id" {
  description = "ID of the AWS Organization (o-xxxxxxxxxx). The central event bus only accepts PutEvents from principals in this org."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && !can(regex("^o-0+$", var.organization_id))
    error_message = "organization_id must be a real organization id (o-...), not the 0000 placeholder."
  }
}

variable "remediation_role_name" {
  description = "Name of the role the Lambda assumes in the member account (governance/account-baseline creates it). Must match that module's role name exactly."
  type        = string
  default     = "security-remediation"
}

variable "alert_topic_arn" {
  description = "ARN of the security/security-alerts SNS topic (that module's output topic_arn, applied in this same account) to publish remediation summaries to."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:sns:", var.alert_topic_arn))
    error_message = "alert_topic_arn must be an SNS topic ARN."
  }
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. Kept short: the whole point is remediating in well under 30 seconds (docs/runbooks/auto-remediation.md)."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout_seconds >= 10 && var.lambda_timeout_seconds <= 60
    error_message = "lambda_timeout_seconds must be between 10 and 60."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda's log group."
  type        = number
  default     = 90
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
