variable "name_prefix" {
  description = "Prefix for all resource names. The Firehose delivery stream is named aws-waf-logs-<name_prefix> (the 'aws-waf-logs-' prefix is required by WAFv2)."
  type        = string
  default     = "platform"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "name_prefix must be 2-21 lowercase letters, digits or hyphens."
  }
}

variable "log_archive_bucket_arn" {
  description = "ARN of the log-archive S3 bucket for WAF logs (security/log-archive's bucket_arns[\"waf\"] output)."
  type        = string

  validation {
    condition     = can(regex("^arn:", var.log_archive_bucket_arn))
    error_message = "log_archive_bucket_arn must be a valid ARN."
  }
}

variable "log_archive_kms_key_arn" {
  description = "ARN of the KMS key used by the WAF log bucket in log-archive. Firehose needs kms:GenerateDataKey and kms:Decrypt."
  type        = string

  validation {
    condition     = can(regex("^arn:", var.log_archive_kms_key_arn))
    error_message = "log_archive_kms_key_arn must be a valid ARN."
  }
}

variable "web_acl_arns" {
  description = "ARNs of the WAFv2 web ACLs to attach logging to. Can be regional or CloudFront (global) web ACLs."
  type        = list(string)
  default     = []
}

variable "redacted_fields" {
  description = <<-EOT
    HTTP request fields to redact from WAF logs. Each entry is a map with one key:
    "single_header" (header name, lowercased), "method", "query_string", or "uri_path".
    Default redacts the authorization and cookie headers.
  EOT
  type = list(object({
    single_header = optional(object({ name = string }))
    method        = optional(object({}))
    query_string  = optional(object({}))
    uri_path      = optional(object({}))
  }))
  default = [
    { single_header = { name = "authorization" }, method = null, query_string = null, uri_path = null },
    { single_header = { name = "cookie" }, method = null, query_string = null, uri_path = null },
  ]
}

variable "buffering_interval" {
  description = "Firehose buffering interval in seconds (60-900)."
  type        = number
  default     = 300

  validation {
    condition     = var.buffering_interval >= 60 && var.buffering_interval <= 900
    error_message = "buffering_interval must be between 60 and 900 seconds."
  }
}

variable "buffering_size" {
  description = "Firehose buffering size in MiB (1-128)."
  type        = number
  default     = 5

  validation {
    condition     = var.buffering_size >= 1 && var.buffering_size <= 128
    error_message = "buffering_size must be between 1 and 128 MiB."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
