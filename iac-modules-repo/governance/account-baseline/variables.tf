variable "account_alias" {
  description = "IAM account alias (globally unique, lowercase). Leave empty to skip the alias."
  type        = string
  default     = ""

  validation {
    condition     = var.account_alias == "" || can(regex("^[a-z0-9][a-z0-9-]{2,62}$", var.account_alias))
    error_message = "account_alias must be 3-63 characters: lowercase letters, digits and hyphens, not starting with a hyphen."
  }
}

variable "env" {
  description = "Environment of this account (dev, staging, prod, global). Used in the discovery parameter names."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "global"], var.env)
    error_message = "env must be one of dev, staging, prod, global."
  }
}

variable "region" {
  description = "Region this module is applied in. Regional settings (EBS encryption, IMDSv2 default, KMS keys) apply to this region only."
  type        = string
}

variable "ou" {
  description = "Name of the OU this account is in. Published as a discovery parameter."
  type        = string
}

variable "password_policy_min_length" {
  description = "Minimum IAM password length. IAM users are discouraged (Identity Center is the human path), this is the floor if one exists."
  type        = number
  default     = 14

  validation {
    condition     = var.password_policy_min_length >= 14 && var.password_policy_min_length <= 128
    error_message = "password_policy_min_length must be between 14 and 128."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a scheduled KMS key deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "publish_ssm_parameters" {
  description = "Publish the account and KMS discovery parameters (/platform/<env>/<region>/account/*, .../kms/*)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
