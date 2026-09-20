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
