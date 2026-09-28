variable "template_body" {
  description = "Body of the account-bootstrap CloudFormation template. The live leaf reads foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml, so this module stays free of file paths."
  type        = string

  validation {
    condition     = length(trimspace(var.template_body)) > 0
    error_message = "template_body must not be empty."
  }
}

variable "stack_sets" {
  description = <<-EOT
    One service-managed StackSet per GitHub Environment, keyed by StackSet name. The name must start
    with "bootstrap-": the apply role's permissions boundary only protects stacks named
    StackSet-bootstrap-*. The GitHub Environment is a StackSet parameter (it sets the apply role's
    trust subject), and auto-deployment can only use the StackSet's own parameters, which is why each
    environment needs its own StackSet.
      github_environment      the GitHub Environment allowed to assume github-actions-apply (dev, prod, core, ...)
      organizational_unit_ids OUs (ou-...) whose accounts get the stack, now and when they join later
  EOT
  type = map(object({
    github_environment      = string
    organizational_unit_ids = list(string)
  }))

  validation {
    condition     = alltrue([for name, _ in var.stack_sets : can(regex("^bootstrap-[a-z0-9-]+$", name))])
    error_message = "Every StackSet name must match ^bootstrap-[a-z0-9-]+$ (the boundary protects StackSet-bootstrap-*)."
  }

  validation {
    condition     = alltrue([for _, s in var.stack_sets : can(regex("^[a-z0-9-]+$", s.github_environment))])
    error_message = "github_environment must match ^[a-z0-9-]+$."
  }

  validation {
    condition = alltrue([
      for _, s in var.stack_sets :
      length(s.organizational_unit_ids) > 0 && alltrue([for ou in s.organizational_unit_ids : can(regex("^ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}$", ou))])
    ])
    error_message = "Every StackSet needs at least one organizational unit ID like ou-ab12-cd34ef56 (a root ID would target the management account and every OU)."
  }

  validation {
    condition     = !contains(flatten([for _, s in var.stack_sets : s.organizational_unit_ids]), "ou-0000-00000000")
    error_message = "organizational_unit_ids still contains the ou-0000-00000000 placeholder. Replace it with the real OU ID."
  }
}

variable "github_repo" {
  description = "GitHub repository (owner/name) whose jobs may assume the CI roles in member accounts."
  type        = string
  default     = "ok-karthik/enterprise-aws-infrastructure"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must look like owner/name."
  }
}

variable "noncurrent_version_days" {
  description = "Days before old versions of state files are deleted in each member account's state bucket."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_days >= 30
    error_message = "noncurrent_version_days must be at least 30."
  }
}

variable "region" {
  description = "Primary region the stack instances are deployed to."
  type        = string
  default     = "eu-central-1"
}

variable "secondary_region" {
  description = <<-EOT
    Optional (PLAN 7.2): a second region to deploy the stacks to. Each account then also gets a state bucket
    there, and the primary bucket replicates every state file to it (one way). "" = primary region only.
    The template creates only the state bucket in that region (the OIDC provider and CI roles are global IAM
    and come from the primary region's stack).
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.secondary_region == "" || (can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.secondary_region)) && var.secondary_region != var.region)
    error_message = "secondary_region must be empty or a region name different from region."
  }
}

variable "tags" {
  description = "Tags set on each StackSet. CloudFormation propagates them to every resource the stacks create in the member accounts."
  type        = map(string)
  default     = {}
}
