variable "account_name" {
  description = "Account name from the registry. Used in budget and monitor names."
  type        = string
}

variable "monthly_limit" {
  description = "Monthly cost budget for this account. In the management account (the payer) it covers the whole organization, so keep it low while nothing runs."
  type        = number

  validation {
    condition     = var.monthly_limit > 0
    error_message = "monthly_limit must be greater than 0."
  }
}

variable "currency" {
  description = "Budget currency. AWS Budgets is billed and reported in USD."
  type        = string
  default     = "USD"
}

variable "notification_emails" {
  description = "Addresses that receive budget alerts and anomaly reports. Real, monitored mailboxes: an alert nobody reads is no alert."
  type        = list(string)

  validation {
    condition     = length(var.notification_emails) > 0 && alltrue([for e in var.notification_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Give at least one valid email address."
  }

  validation {
    condition     = alltrue([for e in var.notification_emails : !endswith(lower(e), "@example.com")])
    error_message = "A notification email still ends in @example.com (a registry placeholder). Replace it with a mailbox you read."
  }
}

variable "notification_sns_topic_arns" {
  description = "Optional SNS topics that also receive the budget alerts. The topic policy must allow budgets.amazonaws.com to publish."
  type        = list(string)
  default     = []
}

variable "anomaly_threshold" {
  description = "Cost Anomaly Detection: report an anomaly when its total impact is at least this amount (in the budget currency)."
  type        = number
  default     = 10

  validation {
    condition     = var.anomaly_threshold > 0
    error_message = "anomaly_threshold must be greater than 0."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
