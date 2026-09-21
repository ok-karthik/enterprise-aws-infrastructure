variable "root_id" {
  description = "AWS Organizations root ID (e.g. r-xxxx). Leave empty if not configuring OUs/SCPs directly."
  type        = string
  default     = ""
}

variable "hub_account_id" {
  description = "Account ID running the ACK controllers (EKS hub)"
  type        = string
  default     = ""
}

variable "spoke_account_id" {
  description = "Account ID that owns the actual AWS resources ACK provisions for one team/environment"
  type        = string
  default     = ""
}

variable "hub_ack_controller_role_arn" {
  description = "The IAM role ARN the ACK controller pods assume via Pod Identity in the hub"
  type        = string
  default     = ""
}

variable "external_id" {
  description = "Shared secret proving the assume-role call is deliberate, preventing confused deputy"
  type        = string
  default     = "platform-ack-shared-secret"
  sensitive   = true
}

variable "allowed_regions" {
  description = "Regions workloads may use. The region SCP denies every request to a region not in this list (global services are exempt)."
  type        = list(string)
  default     = ["eu-central-1"]

  validation {
    condition     = length(var.allowed_regions) > 0 && alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "allowed_regions must be a non-empty list of region names such as \"eu-central-1\"."
  }
}

variable "additional_region_exempt_actions" {
  description = "Extra IAM actions to exempt from the region SCP (added to the built-in global-service list), e.g. [\"ec2:DescribeRegions\"]."
  type        = list(string)
  default     = []
}

variable "ack_s3_bucket_prefix" {
  description = "Name prefix of the S3 buckets the ACK spoke role may manage (and that ACK-created roles may access). Buckets outside this prefix are out of reach."
  type        = string
  default     = "platform-ack-"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,40}$", var.ack_s3_bucket_prefix))
    error_message = "ack_s3_bucket_prefix must be 2-41 chars of lowercase letters, digits, dots or hyphens, and must not be empty (an empty prefix would grant access to every bucket)."
  }
}

variable "ack_role_path" {
  description = "IAM path under which ACK may create roles, without leading slash and with trailing slash (e.g. \"ack/\"). Scopes iam:CreateRole / PassRole to arn:aws:iam::<account>:role/<path>*."
  type        = string
  default     = "ack/"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]+(/[A-Za-z0-9+=,.@_-]+)*/$", var.ack_role_path))
    error_message = "ack_role_path must look like \"ack/\": no leading slash, a trailing slash, and not empty."
  }
}

variable "env" {
  description = "Target environment for discovery contract (e.g. _global, dev, prod)"
  type        = string
  default     = "_global"
}

variable "region" {
  description = "AWS region for discovery contract (e.g. eu-central-1)"
  type        = string
  default     = "eu-central-1"
}

variable "publish_ssm_parameters" {
  description = "Whether to publish discovery contract parameters to SSM Parameter Store"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
