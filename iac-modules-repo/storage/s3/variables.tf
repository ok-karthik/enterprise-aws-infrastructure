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

variable "replication_destination_bucket_arn" {
  type        = string
  description = "Optional (PLAN 7.3): ARN of a versioned bucket in another region that receives a copy of every object. Create it first, with this module in the secondary region. Empty = no replication (the default)."
  default     = ""

  validation {
    condition     = var.replication_destination_bucket_arn == "" || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9.-]{3,63}$", var.replication_destination_bucket_arn))
    error_message = "replication_destination_bucket_arn must be empty or a bucket ARN like arn:aws:s3:::my-bucket."
  }
}
