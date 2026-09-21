variable "env" {
  description = "Environment of this account (dev, staging, prod, global). Part of every parameter name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "global"], var.env)
    error_message = "env must be one of dev, staging, prod, global."
  }
}

variable "region" {
  description = "Region the parameters are published for (part of every parameter name)."
  type        = string
}

variable "parameters" {
  description = <<-EOT
    Discovery parameters to publish, keyed by contract key (the part after /platform/<env>/<region>/), value
    is the string to store. Only keys of the discovery contract are accepted, so tenant modules can rely on
    the names (see docs/DISCOVERY_CONTRACT.md). Values normally come from the outputs of the stacks that own them.
  EOT
  type        = map(string)

  validation {
    condition = alltrue([
      for key, _ in var.parameters : contains([
        "vpc/id",
        "vpc/database_subnets",
        "eks/cluster_name",
        "eks/oidc_provider_arn",
        "ack/cross_account_role_arn",
        "account/id",
        "account/ou",
        "kms/general_key_arn",
        "kms/confidential_key_arn",
        "iam/workload_boundary_arn",
      ], key)
    ])
    error_message = "Every key must be part of the discovery contract: vpc/id, vpc/database_subnets, eks/cluster_name, eks/oidc_provider_arn, ack/cross_account_role_arn, account/id, account/ou, kms/general_key_arn, kms/confidential_key_arn, iam/workload_boundary_arn."
  }

  validation {
    condition     = alltrue([for _, v in var.parameters : length(trimspace(v)) > 0])
    error_message = "Parameter values must not be empty."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
