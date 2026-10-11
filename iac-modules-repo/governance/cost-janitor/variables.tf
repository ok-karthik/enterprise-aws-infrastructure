variable "name" {
  description = "Name prefix for the Lambda, its role, its log group and its schedule"
  type        = string
  default     = "cost-janitor"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "name must be 3-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "dry_run" {
  description = "true = only report. false = delete unattached volumes, old snapshots and unassociated Elastic IPs, and set retention on log groups without one. The delete permissions exist in IAM only when this is false, and never apply to resources tagged keep=true."
  type        = bool
  default     = true
}

variable "volume_min_age_days" {
  description = "An unattached EBS volume is reported (or deleted) only when it is at least this old"
  type        = number
  default     = 14
}

variable "snapshot_min_age_days" {
  description = "An EBS snapshot owned by this account is reported (or deleted) only when it is at least this old. Snapshots used by an AMI and AWS Backup snapshots are always skipped."
  type        = number
  default     = 30
}

variable "default_log_retention_days" {
  description = "Retention set on log groups that have none (only when dry_run = false). Must be a value CloudWatch Logs accepts."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.default_log_retention_days)
    error_message = "default_log_retention_days must be a retention CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}

variable "exclude_log_group_prefixes" {
  description = "Log groups whose name starts with one of these are ignored"
  type        = list(string)
  default     = []
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression for the run"
  type        = string
  default     = "cron(0 9 ? * MON *)"
}

variable "schedule_timezone" {
  description = "Time zone of schedule_expression"
  type        = string
  default     = "Europe/Berlin"
}

variable "alert_topic_arn" {
  description = "Optional SNS topic that gets a short text version of each run. null = only the CloudWatch Logs summary."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention of the Lambda's own log group"
  type        = number
  default     = 30
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
