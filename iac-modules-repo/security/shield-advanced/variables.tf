variable "enabled" {
  description = <<-EOT
    Enable Shield Advanced subscription. This costs $3,000/month per organization (not per account).
    Set to true ONLY for prod OU after reviewing the cost impact in docs/FINOPS.md.
  EOT
  type        = bool
  default     = false
}

variable "protected_resources" {
  description = <<-EOT
    Map of resource ARNs to protect with Shield Advanced. Each key is a friendly name, each value
    is the ARN. Supports CloudFront distributions, ALBs, EIPs, Route 53 hosted zones and
    Global Accelerators.
  EOT
  type        = map(string)
  default     = {}
}

variable "proactive_engagement_contacts" {
  description = <<-EOT
    Contacts for Shield Response Team (SRT) proactive engagement during DDoS events.
    Each entry must have email_address, phone_number and an optional note.
  EOT
  type = list(object({
    email_address = string
    phone_number  = string
    note          = optional(string, "")
  }))
  default = []

  validation {
    condition     = alltrue([for c in var.proactive_engagement_contacts : can(regex("@", c.email_address))])
    error_message = "Every proactive_engagement_contact must have a valid email_address."
  }

  validation {
    condition     = alltrue([for c in var.proactive_engagement_contacts : can(regex("^\\+[1-9]\\d{1,14}$", c.phone_number))])
    error_message = "Every proactive_engagement_contact phone_number must be in E.164 format, e.g. +15555555555."
  }
}

variable "enable_proactive_engagement" {
  description = "Enable proactive engagement with the AWS Shield Response Team during DDoS events."
  type        = bool
  default     = false
}

variable "enable_auto_remediation" {
  description = "Enable automatic application-layer DDoS mitigation (WAF rate-based rules created by Shield)."
  type        = bool
  default     = true
}

variable "auto_remediation_action" {
  description = "Action for auto-remediation: COUNT (observe) or BLOCK."
  type        = string
  default     = "COUNT"

  validation {
    condition     = contains(["COUNT", "BLOCK"], var.auto_remediation_action)
    error_message = "auto_remediation_action must be COUNT or BLOCK."
  }
}

variable "drt_access_role_arn" {
  description = "ARN of the IAM role that grants the Shield Response Team access to your WAF resources. Empty = no DRT access."
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
