variable "unused_access_age_days" {
  description = "A role or user counts as unused after this many days without activity, and unused permissions are reported as findings."
  type        = number
  default     = 90

  validation {
    condition     = var.unused_access_age_days >= 1 && var.unused_access_age_days <= 365
    error_message = "unused_access_age_days must be between 1 and 365."
  }
}

variable "external_analyzer_name" {
  description = "Name of the organization analyzer for external access (resources shared outside the organization)"
  type        = string
  default     = "org-external-access"
}

variable "unused_analyzer_name" {
  description = "Name of the organization analyzer for unused access"
  type        = string
  default     = "org-unused-access"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
