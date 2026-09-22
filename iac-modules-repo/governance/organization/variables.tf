variable "organizational_units" {
  description = <<-EOT
    The OU tree, two levels deep. Key = OU name. `parent` is null for a top-level OU (directly under the
    root) or the name of a top-level OU. Default is the target layout of PLAN.md: Security and
    Infrastructure, Workloads with Prod and NonProd, Sandbox, Policy-Staging (test SCPs here first) and
    Suspended (accounts waiting to be closed).
  EOT
  type = map(object({
    parent = optional(string)
  }))
  default = {
    "Security"       = {}
    "Infrastructure" = {}
    "Workloads"      = {}
    "Prod"           = { parent = "Workloads" }
    "NonProd"        = { parent = "Workloads" }
    "Sandbox"        = {}
    "Policy-Staging" = {}
    "Suspended"      = {}
  }

  validation {
    condition = alltrue([
      for name, ou in var.organizational_units :
      ou.parent == null || (contains(keys(var.organizational_units), ou.parent == null ? "" : ou.parent) && try(var.organizational_units[ou.parent].parent, "x") == null)
    ])
    error_message = "Every parent must be the name of a TOP-LEVEL OU in this map (AWS allows deeper trees, this module supports two levels)."
  }

  validation {
    condition     = alltrue([for name, _ in var.organizational_units : can(regex("^[A-Za-z0-9][A-Za-z0-9 _-]{0,127}$", name))])
    error_message = "OU names must be 1-128 characters: letters, digits, space, hyphen or underscore."
  }
}

variable "aws_service_access_principals" {
  description = <<-EOT
    AWS services that may integrate with the organization (trusted access). AUTHORITATIVE: any principal
    enabled by hand and missing here is disabled on apply, so check the plan. The default keeps the StackSets
    access that bootstrap.sh enables and adds what PLAN phases 2 to 6 need.
  EOT
  type        = list(string)
  default = [
    "member.org.stacksets.cloudformation.amazonaws.com", # bootstrap StackSets (PLAN 2.0b)
    "sso.amazonaws.com",                                 # IAM Identity Center (3.1)
    "account.amazonaws.com",                             # account management
    "iam.amazonaws.com",                                 # centralized root access (3.5)
    "access-analyzer.amazonaws.com",                     # 3.6
    "cloudtrail.amazonaws.com",                          # org trail (4.2)
    "config.amazonaws.com",                              # 4.3
    "guardduty.amazonaws.com",                           # 4.4
    "securityhub.amazonaws.com",                         # 4.4
    "inspector2.amazonaws.com",                          # 4.4
    "macie.amazonaws.com",                               # 4.4
    "backup.amazonaws.com",                              # 4.6
    "tagpolicies.tag.amazonaws.com",                     # 4.6
    "ram.amazonaws.com",                                 # network sharing (5.x)
    "ipam.amazonaws.com",                                # 5.1
    "fms.amazonaws.com",                                 # 6.1
  ]
}

variable "enable_centralized_root_access" {
  description = "Enable centralized root access management (RootCredentialsManagement and RootSessions), so member accounts need no root credentials. See docs/ROOT_ACCESS.md."
  type        = bool
  default     = true
}

variable "delegated_administrators" {
  description = <<-EOT
    Delegated administrator accounts: service principal => account id, for example
    { "access-analyzer.amazonaws.com" = "<security-tooling account id>" }. Each service needs trusted access in
    aws_service_access_principals. Leave a service out until its account really exists (no placeholder ids).
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for _, id in var.delegated_administrators : can(regex("^[0-9]{12}$", id)) && !startswith(id, "00000000")])
    error_message = "Every delegated administrator needs a real 12-digit account id (a 000000000xxx registry placeholder is refused)."
  }

  validation {
    condition     = alltrue([for principal, _ in var.delegated_administrators : contains(var.aws_service_access_principals, principal)])
    error_message = "Every delegated service needs trusted access: add its principal to aws_service_access_principals."
  }
}

variable "enabled_policy_types" {
  description = "Policy types enabled on the organization root. Must include SERVICE_CONTROL_POLICY."
  type        = list(string)
  default = [
    "SERVICE_CONTROL_POLICY",
    "RESOURCE_CONTROL_POLICY",
    "TAG_POLICY",
    "BACKUP_POLICY",
    "DECLARATIVE_POLICY_EC2",
  ]

  validation {
    condition     = contains(var.enabled_policy_types, "SERVICE_CONTROL_POLICY")
    error_message = "enabled_policy_types must include SERVICE_CONTROL_POLICY: the guardrails are SCPs."
  }
}

variable "guardrail_target_ous" {
  description = <<-EOT
    OUs the baseline SCP guardrails are attached to. Starts with Policy-Staging only, so a new SCP is tested on
    throw-away accounts before it can lock real ones out (PLAN 4.6). Widen it deliberately, for example
    ["Policy-Staging", "Sandbox", "NonProd"], then the rest.
  EOT
  type        = list(string)
  default     = ["Policy-Staging"]
}

variable "allowed_regions_by_ou" {
  description = <<-EOT
    Regions each OU may use (PLAN 4.6), keyed by OU name; matches _config/regions.hcl's allowed_regions_by_ou.
    One region SCP per key, attached only to that OU: an OU with no entry (or an empty list) gets no region
    SCP from this module at all. Starts empty by default so nothing widens past guardrail_target_ous without
    a deliberate choice by the caller (the live envcommon passes only the OUs it wants tested).
  EOT
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for ou, regions in var.allowed_regions_by_ou :
      alltrue([for r in regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    ])
    error_message = "Every region must look like \"eu-central-1\"."
  }
}

variable "additional_region_exempt_actions" {
  description = "Extra IAM actions to exempt from every region SCP (added to the built-in global-service list), e.g. [\"ec2:DescribeRegions\"]."
  type        = list(string)
  default     = []
}

variable "break_glass_role_arn_pattern" {
  description = <<-EOT
    ARN pattern (StringLike) matching a BreakGlassAdmin session, used as an exception in the guardrails that
    name one (deny_iam_user_creation, protect_platform_resources). Matches the Identity Center permission set
    role naming that security/break-glass-alerts also matches (role_glob there).
  EOT
  type        = string
  default     = "arn:*:sts::*:assumed-role/AWSReservedSSO_BreakGlassAdmin_*/*"

  validation {
    condition     = strcontains(var.break_glass_role_arn_pattern, "assumed-role")
    error_message = "break_glass_role_arn_pattern must be an assumed-role ARN pattern (SCPs match principals by ARN, not by a Principal element)."
  }
}

variable "enable_sandbox_guardrails" {
  description = "Attach the Sandbox-only guardrails (deny large instance families, deny RI/Savings Plan purchases) to the Sandbox OU. Off by default: the Sandbox account is the owner's free-experimentation zone (learning-plan labs), turned on deliberately."
  type        = bool
  default     = false
}

variable "enable_suspended_deny_all" {
  description = "Attach a deny-everything SCP to the Suspended OU. Safe by construction: the OU starts empty, so this has no effect until an account is actually moved there."
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
