variable "notification_emails" {
  description = "Addresses that are told about every alert this module raises. Real, monitored mailboxes. Each address must confirm the SNS subscription once."
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

variable "name_prefix" {
  description = "Prefix of every alert resource."
  type        = string
  default     = "security-alerts"
}

variable "enable_guardduty_findings" {
  description = "Alert on GuardDuty findings at or above guardduty_minimum_severity. Turn on where GuardDuty findings actually land: the delegated administrator account (security-tooling)."
  type        = bool
  default     = false
}

variable "guardduty_minimum_severity" {
  description = "Minimum GuardDuty finding severity that alerts (GuardDuty's HIGH band starts at 7.0)."
  type        = number
  default     = 7.0

  validation {
    condition     = var.guardduty_minimum_severity >= 0 && var.guardduty_minimum_severity <= 10
    error_message = "guardduty_minimum_severity must be between 0 and 10."
  }
}

variable "enable_securityhub_findings" {
  description = "Alert on new Security Hub findings at securityhub_severity_labels. Turn on where Security Hub findings land: the delegated administrator account (security-tooling)."
  type        = bool
  default     = false
}

variable "securityhub_severity_labels" {
  description = "Security Hub severity labels that alert."
  type        = list(string)
  default     = ["HIGH", "CRITICAL"]

  validation {
    condition     = length(var.securityhub_severity_labels) > 0 && alltrue([for l in var.securityhub_severity_labels : contains(["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"], l)])
    error_message = "securityhub_severity_labels may only contain INFORMATIONAL, LOW, MEDIUM, HIGH, CRITICAL."
  }
}

variable "enable_root_sign_in" {
  description = <<-EOT
    Alert on any sign-in or API call as the account's root user (console or CLI). Root sign-in only matters where
    root credentials still exist: the management account (member accounts have theirs removed, PLAN 3.5, and
    docs/ROOT_ACCESS.md's break-glass root tasks are a separate, already-alerted path via security/break-glass-alerts).
  EOT
  type        = bool
  default     = false
}

variable "enable_scp_changes" {
  description = "Alert on Organizations policy changes (SCP/RCP/tag/backup/declarative policy create, update, delete, attach, detach, or a policy type enabled/disabled). Organizations is only managed from the management account, so this only makes sense there."
  type        = bool
  default     = false
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a scheduled deletion of the topic's KMS key."
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
