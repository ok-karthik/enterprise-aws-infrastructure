variable "is_primary_region" {
  description = "Whether this is the primary region for cross-region aggregation and conformance packs"
  type        = bool
  default     = false
}

variable "allowed_regions" {
  description = "List of AWS regions to aggregate config data from"
  type        = list(string)
  default     = ["eu-central-1", "eu-west-1"]
}

variable "config_delivery_bucket_name" {
  description = "S3 bucket name in log-archive where AWS Config delivers snapshots and history"
  type        = string
}

variable "enable_cis_conformance_pack" {
  description = "Whether to deploy the Operational Best Practices for CIS AWS Foundations Benchmark conformance pack"
  type        = bool
  default     = true
}

variable "enable_nist_800_53_conformance_pack" {
  description = "Whether to deploy the Operational Best Practices for NIST 800-53 rev 5 conformance pack"
  type        = bool
  default     = true
}

variable "enable_soc2_conformance_pack" {
  description = "Whether to deploy the Operational Best Practices for AICPA SOC2 conformance pack"
  type        = bool
  default     = true
}

variable "excluded_accounts" {
  description = "List of AWS account IDs to exclude from organization conformance packs"
  type        = list(string)
  default     = []
}

variable "snapshot_delivery_frequency" {
  description = "Frequency with which AWS Config delivers configuration snapshots"
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"
    ], var.snapshot_delivery_frequency)
    error_message = "snapshot_delivery_frequency must be one of One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
