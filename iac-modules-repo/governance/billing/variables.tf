variable "name" {
  description = "Name prefix for the export and the bucket (for example platform-billing)"
  type        = string
  default     = "platform-billing"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "name must be 3-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "export_retention_days" {
  description = "Days the CUR files are kept in the bucket. Billing data is needed for audits for years, so the default keeps 13 months hot and expires after that; archive elsewhere if you must keep more."
  type        = number
  default     = 400

  validation {
    condition     = var.export_retention_days >= 90
    error_message = "export_retention_days must be at least 90."
  }
}

variable "anomaly_ou_accounts" {
  description = "OU name => list of 12-digit account IDs in it. One Cost Anomaly Detection monitor is created per OU (only accounts with real IDs; leave placeholders out). The organization-wide per-service monitor is always created."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for _, ids in var.anomaly_ou_accounts : alltrue([for id in ids : can(regex("^[0-9]{12}$", id))])])
    error_message = "Every account ID in anomaly_ou_accounts must be 12 digits."
  }
}

variable "anomaly_alert_emails" {
  description = "Who gets the daily anomaly summary. At least one address."
  type        = list(string)

  validation {
    condition     = length(var.anomaly_alert_emails) > 0 && alltrue([for e in var.anomaly_alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e)) && !endswith(e, "@example.com")])
    error_message = "anomaly_alert_emails needs at least one real address (not @example.com)."
  }
}

variable "anomaly_threshold_usd" {
  description = "Alert when an anomaly's total impact is at least this many US dollars."
  type        = number
  default     = 20

  validation {
    condition     = var.anomaly_threshold_usd > 0
    error_message = "anomaly_threshold_usd must be greater than 0."
  }
}

variable "cost_allocation_tags" {
  description = "Tag keys to activate for cost allocation (they then appear in the CUR and Cost Explorer, which is what the CostCenter showback needs). A key can only be activated after a resource with it has been seen in billing data (up to 24 hours after tagging), so leave this empty until then."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags for the bucket and the monitors"
  type        = map(string)
  default     = {}
}
