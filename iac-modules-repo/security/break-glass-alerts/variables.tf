variable "permission_set_name" {
  description = "Name of the break-glass permission set in Identity Center. Its roles are named AWSReservedSSO_<name>_<hash>."
  type        = string
  default     = "BreakGlassAdmin"

  validation {
    condition     = can(regex("^[A-Za-z0-9_+=,.@-]{1,32}$", var.permission_set_name))
    error_message = "permission_set_name must be a valid Identity Center permission set name."
  }
}

variable "notification_emails" {
  description = "Addresses that are told about every break-glass sign-in. Real, monitored mailboxes. Each address must confirm the SNS subscription once."
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

variable "enable_sso_portal_rule" {
  description = <<-EOT
    Also alert on the IAM Identity Center portal calls (Federate / GetRoleCredentials). These are the only events
    that show CLI sign-ins, and they are logged in the MANAGEMENT account, so turn this on there and nowhere else.
  EOT
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix of the alert resources"
  type        = string
  default     = "break-glass"
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
