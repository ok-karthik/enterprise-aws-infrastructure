variable "team_name" {
  type        = string
  description = "Team or tenant that owns this identity"
}

variable "app_name" {
  type        = string
  description = "Application the identity belongs to"
}

variable "env" {
  type        = string
  description = "Target environment (dev, staging, prod)"
  default     = "dev"
}

# tflint-ignore: terraform_unused_declarations
variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource, supplied by the scaffolder"
  default     = {}
}
