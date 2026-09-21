variable "accounts" {
  description = <<-EOT
    Member accounts to manage, keyed by account name (from the account registry, only the entries with
    create = true). `ou` is the name of an OU in var.ou_ids. `email` is the account's root email and cannot be
    changed lightly afterwards. An account created by hand must be IMPORTED before the first apply.
  EOT
  type = map(object({
    email = string
    ou    = string
  }))

  validation {
    condition     = alltrue([for name, _ in var.accounts : can(regex("^[A-Za-z0-9][A-Za-z0-9 _.-]{1,49}$", name))])
    error_message = "Account names must be 2-50 characters: letters, digits, space, dot, hyphen or underscore."
  }

  validation {
    condition     = alltrue([for _, a in var.accounts : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", a.email))])
    error_message = "Every account needs a valid root email address."
  }

  validation {
    condition     = alltrue([for _, a in var.accounts : !endswith(lower(a.email), "@example.com")])
    error_message = "An account email still ends in @example.com (the registry placeholder). Replace it with the real root email: an account cannot be created with an address you do not own."
  }

  validation {
    condition     = alltrue([for _, a in var.accounts : contains(keys(var.ou_ids), a.ou)])
    error_message = "Every account's ou must be the name of an OU in ou_ids (the organization module's organizational_unit_ids output)."
  }

  validation {
    condition     = length(distinct([for _, a in var.accounts : lower(a.email)])) == length(var.accounts)
    error_message = "Every account needs its own root email address."
  }
}

variable "ou_ids" {
  description = "Map of OU name to OU ID (the organization module's organizational_unit_ids output)."
  type        = map(string)
}

variable "role_name" {
  description = "Name of the admin role AWS creates in each new account for the management account to assume. Only used when an account is created."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
