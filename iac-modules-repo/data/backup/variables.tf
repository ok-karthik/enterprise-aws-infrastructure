variable "name" {
  type        = string
  description = "Name prefix for the vault, plan and role (for example platform-prod)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name))
    error_message = "name must be 3-41 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key in THIS region that encrypts the vault. A vault cannot share a key across regions, so the secondary region needs its own."
}

variable "create_plan" {
  type        = bool
  description = "Create the backup plan and tag selection. Set false in a region that only holds a copy destination vault."
  default     = true
}

variable "copy_destination_vault_arn" {
  type        = string
  description = "Optional (PLAN 7.3): ARN of the vault in another region that receives a copy of every recovery point. Create it first, with this module in the secondary region (create_plan = false). Empty = no cross-region copy."
  default     = ""

  validation {
    condition     = var.copy_destination_vault_arn == "" || can(regex("^arn:aws[a-z-]*:backup:[a-z0-9-]+:[0-9]{12}:backup-vault:.+$", var.copy_destination_vault_arn))
    error_message = "copy_destination_vault_arn must be empty or a Backup vault ARN."
  }
}

variable "schedule" {
  type        = string
  description = "Cron expression (UTC) for the daily backup"
  default     = "cron(0 3 * * ? *)"
}

variable "retention_days" {
  type        = number
  description = "Days a recovery point in this region is kept"
  default     = 35

  validation {
    condition     = var.retention_days >= 7
    error_message = "retention_days must be at least 7."
  }
}

variable "copy_retention_days" {
  type        = number
  description = "Days the cross-region copy is kept"
  default     = 35

  validation {
    condition     = var.copy_retention_days >= 7
    error_message = "copy_retention_days must be at least 7."
  }
}

variable "selection_tag_key" {
  type        = string
  description = "Resources carrying this tag key with the value selection_tag_value are backed up. Tag-based, so tenants opt in without touching this stack."
  default     = "Backup"
}

variable "selection_tag_value" {
  type        = string
  description = "Value of the selection tag"
  default     = "true"
}

variable "tags" {
  type        = map(string)
  description = "Extra tags for the vault, plan and role"
  default     = {}
}
