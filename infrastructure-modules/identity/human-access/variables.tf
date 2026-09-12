variable "sso_instance_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM Identity Center instance"
  type        = string
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

variable "tags" {
  description = "A map of tags to add to all permission set resources"
  type        = map(string)
  default     = {}
}
