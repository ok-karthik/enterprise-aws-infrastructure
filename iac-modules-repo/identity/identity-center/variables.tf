variable "groups" {
  description = <<-EOT
    Names of the groups assigned to accounts. With an external IdP (Okta, Entra ID, Google) the groups are synced
    by SCIM and only READ here (manage_groups = false); the names must match the IdP group display names exactly.
  EOT
  type        = list(string)
  default     = []
}

variable "manage_groups" {
  description = "Create the groups in the Identity Center identity store. Leave false with an external IdP: SCIM owns the groups and Terraform only looks them up."
  type        = bool
  default     = false
}

variable "accounts" {
  description = "Accounts that can be assigned, from the account registry: name => { id, ou }. Pass only accounts with a real account id."
  type = map(object({
    id = string
    ou = string
  }))
  default = {}

  validation {
    condition     = alltrue([for _, a in var.accounts : can(regex("^[0-9]{12}$", a.id)) && !startswith(a.id, "00000000")])
    error_message = "Every account needs a real 12-digit id (a 000000000xxx registry placeholder cannot be assigned)."
  }
}

variable "assignments" {
  description = <<-EOT
    Who gets what where: OU name => group name => permission set names. Expanded to every account in that OU
    using var.accounts. The management account has the OU name "Root". Example:
      { NonProd = { developers = ["Developer"] }, Prod = { developers = ["ReadOnly"] } }
  EOT
  type        = map(map(list(string)))
  default     = {}

  validation {
    condition     = alltrue(flatten([for _, groups in var.assignments : [for _, sets in groups : [for s in sets : contains(keys(local.permission_sets), s)]]]))
    error_message = "Unknown permission set. The catalog is ReadOnly, Developer, PlatformEngineer, SecurityAudit, Billing, BreakGlassAdmin."
  }

  validation {
    condition     = alltrue(flatten([for _, groups in var.assignments : [for g, _ in groups : contains(var.groups, g)]]))
    error_message = "Every group used in assignments must be listed in var.groups."
  }

  validation {
    condition     = var.allow_static_break_glass || !anytrue(flatten([for _, groups in var.assignments : [for _, sets in groups : contains(sets, "BreakGlassAdmin")]]))
    error_message = "BreakGlassAdmin is never assigned statically: it is granted just in time (docs/BREAK_GLASS.md). Set allow_static_break_glass only for a deliberate exception."
  }

  validation {
    condition = alltrue(flatten([
      for ou, groups in var.assignments : [for _, sets in groups :
        !contains(var.jit_only_ous, ou) || length(setintersection(toset(sets), toset(var.elevated_permission_sets))) == 0
      ]
    ]))
    error_message = "Elevated permission sets (PlatformEngineer, BreakGlassAdmin) cannot be assigned statically in the OUs listed in jit_only_ous (Prod): use just-in-time access (docs/BREAK_GLASS.md)."
  }

  validation {
    condition = alltrue(flatten([
      for ou, groups in var.assignments : [for _, sets in groups :
        !contains(sets, "Developer") || contains(var.developer_ous, ou)
      ]
    ]))
    error_message = "Developer can only be assigned in the OUs listed in developer_ous (NonProd, Sandbox, Policy-Staging). Use ReadOnly in Prod."
  }
}

variable "allow_static_break_glass" {
  description = "Allow BreakGlassAdmin in var.assignments. Off by default: break-glass access is just-in-time."
  type        = bool
  default     = false
}

variable "elevated_permission_sets" {
  description = "Permission sets that can change IAM or everything. They get 1-hour sessions and cannot be assigned statically in jit_only_ous."
  type        = list(string)
  default     = ["PlatformEngineer", "BreakGlassAdmin"]
}

variable "jit_only_ous" {
  description = "OUs where elevated permission sets are only granted just in time."
  type        = list(string)
  default     = ["Prod"]
}

variable "developer_ous" {
  description = "OUs where the Developer permission set may be assigned."
  type        = list(string)
  default     = ["NonProd", "Sandbox", "Policy-Staging"]
}

variable "session_durations" {
  description = "Session length per permission set (ISO 8601). 1 hour for the elevated sets, 8 hours for the rest."
  type        = map(string)
  default = {
    ReadOnly         = "PT8H"
    Developer        = "PT8H"
    PlatformEngineer = "PT1H"
    SecurityAudit    = "PT8H"
    Billing          = "PT8H"
    BreakGlassAdmin  = "PT1H"
  }

  validation {
    condition     = alltrue([for _, d in var.session_durations : can(regex("^PT([1-9]|1[0-2])H$|^PT(15|30|45)M$", d))])
    error_message = "Session durations must be between 15 minutes and 12 hours, for example PT1H or PT8H."
  }
}

variable "abac_attributes" {
  description = <<-EOT
    Attributes for access control (ABAC): session tag name => IdP attribute path. The tags become
    aws:PrincipalTag/<name> in every session, for example `team` and `cost_center` (used by the Developer
    policy to scope EC2 by team). The paths depend on your IdP's SCIM attributes: check them before applying.
  EOT
  type        = map(string)
  default = {
    team        = "$${path:enterprise.department}" # TODO(owner): match your IdP's attribute for the team
    cost_center = "$${path:enterprise.costCenter}" # TODO(owner): match your IdP's attribute for the cost center
  }
}

variable "developer_policy_name" {
  description = "Name of the customer-managed policy in every account that the Developer permission set attaches (created by governance/account-baseline)."
  type        = string
  default     = "platform-developer"
}

variable "workload_boundary_name" {
  description = "Name of the permissions boundary in every account (created by governance/account-baseline). The Developer set is capped by it, and PlatformEngineer can only create roles that carry it."
  type        = string
  default     = "platform-workload-boundary"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
