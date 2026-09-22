variable "organization_id" {
  description = "ID of the AWS Organization (o-xxxxxxxxxx). Every RCP denies access from any principal outside it."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && !can(regex("^o-0+$", var.organization_id))
    error_message = "organization_id must be a real organization id (o-...), not the 0000 placeholder."
  }
}

variable "target_ou_ids" {
  description = <<-EOT
    OU name => OU id (governance/organization's organizational_unit_ids output), for the OUs in var.target_ous.
    This module does not own the OU tree, so it takes the ids as an input rather than re-deriving them.
  EOT
  type        = map(string)
}

variable "target_ous" {
  description = "OUs each RCP is attached to. Starts with Policy-Staging only (PLAN 4.6, same reasoning as governance/organization's guardrail_target_ous): test on throw-away accounts before widening it. Every entry must be a key of var.target_ou_ids."
  type        = list(string)
  default     = ["Policy-Staging"]

  validation {
    condition     = alltrue([for ou in var.target_ous : contains(keys(var.target_ou_ids), ou)])
    error_message = "Every OU in target_ous must be a key of target_ou_ids."
  }
}

variable "enabled_services" {
  description = <<-EOT
    Which services get a data-perimeter RCP. s3, kms, sqs and secretsmanager are the low-risk ones: they only
    deny access from OUTSIDE the organization, which nothing legitimate inside the platform needs. sts is
    NOT enabled by default: an RCP on STS also covers the identity-federation actions that create the
    org's first session (GitHub OIDC, SAML into Identity Center) - see the README before adding it, and
    widen it last, after s3/kms/sqs/secretsmanager have been proven on Policy-Staging.
  EOT
  type        = list(string)
  default     = ["s3", "kms", "sqs", "secretsmanager"]

  validation {
    condition     = length(var.enabled_services) > 0 && alltrue([for s in var.enabled_services : contains(["s3", "kms", "sqs", "secretsmanager", "sts"], s)])
    error_message = "enabled_services may only contain s3, kms, sqs, secretsmanager, sts (the services RCPs support at the time this module was written; check the current AWS documentation before adding a new one)."
  }
}

variable "sts_federation_exempt_actions" {
  description = <<-EOT
    STS actions exempt from the organization-membership check, because the caller has no aws:PrincipalOrgID
    until AFTER the action succeeds (it is how they join the org's identity in the first place):
    AssumeRoleWithWebIdentity (GitHub Actions OIDC) and AssumeRoleWithSAML (IAM Identity Center federation from
    the IdP). Only used when "sts" is in enabled_services. Denying these outright would lock out CI and human
    sign-in.
  EOT
  type        = list(string)
  default     = ["sts:AssumeRoleWithWebIdentity", "sts:AssumeRoleWithSAML"]
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
