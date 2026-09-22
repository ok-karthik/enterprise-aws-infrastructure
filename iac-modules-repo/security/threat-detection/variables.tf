variable "is_primary_region" {
  description = <<-EOT
    Whether this call is the primary region. GuardDuty, Security Hub, Inspector v2 and Macie are regional
    services, so this module is meant to be applied in every allowed region; each region gets its own detector /
    account-enablement / org auto-enable configuration. A few resources are NOT regional in effect (the Security
    Hub cross-region finding aggregator, and Detective, which this module only stands up once) and are created
    only when this is true.
  EOT
  type        = bool
  default     = true
}

variable "guardduty_finding_publishing_frequency" {
  description = "How often GuardDuty exports findings to CloudWatch Events."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_publishing_frequency)
    error_message = "guardduty_finding_publishing_frequency must be FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

variable "guardduty_auto_enable_organization_members" {
  description = "ALL: every current and future member gets GuardDuty automatically. NEW: only accounts that join later. NONE: no auto-enable."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "NEW", "NONE"], var.guardduty_auto_enable_organization_members)
    error_message = "guardduty_auto_enable_organization_members must be ALL, NEW or NONE."
  }
}

variable "guardduty_features" {
  description = "GuardDuty protection plans to auto-enable organization-wide. EKS_RUNTIME_MONITORING also turns on the EKS add-on management sub-feature, so GuardDuty manages the runtime agent add-on itself."
  type        = list(string)
  default     = ["S3_DATA_EVENTS", "EKS_AUDIT_LOGS", "EKS_RUNTIME_MONITORING", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS"]

  validation {
    condition = alltrue([
      for f in var.guardduty_features : contains([
        "S3_DATA_EVENTS", "EKS_AUDIT_LOGS", "EKS_RUNTIME_MONITORING", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS",
      ], f)
    ])
    error_message = "guardduty_features may only contain S3_DATA_EVENTS, EKS_AUDIT_LOGS, EKS_RUNTIME_MONITORING, EBS_MALWARE_PROTECTION, RDS_LOGIN_EVENTS, LAMBDA_NETWORK_LOGS."
  }
}

variable "securityhub_standards" {
  description = "Security Hub standards to subscribe to, by short name."
  type        = list(string)
  default     = ["fsbp", "cis-v3"]

  validation {
    condition     = alltrue([for s in var.securityhub_standards : contains(["fsbp", "cis-v3"], s)])
    error_message = "securityhub_standards may only contain fsbp (AWS Foundational Security Best Practices) or cis-v3 (CIS AWS Foundations Benchmark v3.0.0)."
  }
}

variable "securityhub_auto_enable_controls" {
  description = "Whether new controls added to a subscribed standard are enabled automatically."
  type        = bool
  default     = true
}

variable "inspector2_resource_types" {
  description = "Resource types Inspector v2 scans, both for this account and (auto-enable) for every organization member."
  type        = list(string)
  default     = ["EC2", "ECR", "LAMBDA"]

  validation {
    condition     = length(var.inspector2_resource_types) > 0 && alltrue([for t in var.inspector2_resource_types : contains(["EC2", "ECR", "LAMBDA"], t)])
    error_message = "inspector2_resource_types may only contain EC2, ECR, LAMBDA."
  }
}

variable "enable_macie" {
  description = "Enable Macie in this account and auto-enable it organization-wide."
  type        = bool
  default     = true
}

variable "macie_finding_publishing_frequency" {
  description = "How often Macie exports findings to CloudWatch Events / EventBridge."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.macie_finding_publishing_frequency)
    error_message = "macie_finding_publishing_frequency must be FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

variable "enable_detective" {
  description = "Create an Amazon Detective behavior graph and auto-enable it organization-wide (needs GuardDuty enabled for at least 48 hours in an account before Detective can invite it, per AWS)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
