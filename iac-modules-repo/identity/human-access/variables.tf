variable "sso_instance_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM Identity Center instance (leave empty if managing cluster access entries only)"
  type        = string
  default     = ""
}

variable "name_prefix" {
  description = "Prefix prepended to permission set names (e.g. Enterprise, Dev, Prod)"
  type        = string
  default     = "Enterprise"
}

variable "session_duration" {
  description = "The length of time that the application user sessions are valid (e.g. PT4H, PT8H, PT12H)"
  type        = string
  default     = "PT8H"
}

variable "break_glass_session_duration" {
  description = "Session length for the BreakGlassAdmin permission set. Keep it short (ISO 8601, max PT1H)."
  type        = string
  default     = "PT1H"

  validation {
    condition     = contains(["PT15M", "PT30M", "PT45M", "PT1H"], var.break_glass_session_duration)
    error_message = "break_glass_session_duration must be one of PT15M, PT30M, PT45M or PT1H."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary ARN. When set, PlatformEngineers can only create or modify roles under role/platform/* that carry this boundary."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the EKS cluster to grant access entries for"
  type        = string
  default     = ""
}

variable "team_access" {
  description = "Map of (team, tier) access configurations with principal ARN and kubernetes groups"
  type = map(object({
    principal_arn = string
    k8s_groups    = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
