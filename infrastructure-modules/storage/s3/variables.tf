variable "team_name" {
  type        = string
  description = "Team or tenant that owns this bucket"
}

variable "app_name" {
  type        = string
  description = "Application the bucket belongs to"
}

variable "env" {
  type        = string
  description = "Target environment (dev, staging, prod)"
  default     = "dev"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource, supplied by the scaffolder"
  default     = {}
}
