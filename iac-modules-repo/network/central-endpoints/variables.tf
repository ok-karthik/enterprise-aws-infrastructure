variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "central-endpoints"
}

variable "vpc_cidr" {
  description = "CIDR for the shared-endpoints VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread the interface endpoints across."
  type        = list(string)

  validation {
    condition     = length(var.azs) > 0
    error_message = "azs must not be empty."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the endpoints on 443 (normally the platform's whole IPAM address space, so every spoke VPC is covered without listing each one)."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "allowed_cidr_blocks must not be empty."
  }
}

variable "services" {
  description = <<-EOT
    Short service names to create an interface endpoint (and a matching shareable private hosted zone) for.
    "ecr_api" and "ecr_dkr" are ECR's two distinct endpoints; the rest are the AWS service name as used in
    com.amazonaws.<region>.<service>.
  EOT
  type        = list(string)
  default     = ["ecr_api", "ecr_dkr", "sts", "ssm", "ssmmessages", "ec2messages", "logs", "kms", "secretsmanager", "eks"]

  validation {
    condition = alltrue([
      for s in var.services : contains([
        "ecr_api", "ecr_dkr", "sts", "ssm", "ssmmessages", "ec2messages", "logs", "kms", "secretsmanager", "eks",
      ], s)
    ])
    error_message = "services may only contain ecr_api, ecr_dkr, sts, ssm, ssmmessages, ec2messages, logs, kms, secretsmanager, eks."
  }
}

variable "spoke_vpcs" {
  description = <<-EOT
    Spoke VPCs to share every service's private hosted zone with, so they resolve the endpoints centrally.
    Every real spoke is in a DIFFERENT account, so this only creates the authorization side
    (aws_route53_vpc_association_authorization) here; the spoke account must create its own
    aws_route53_zone_association for each zone (not built by this module -- see the README).
  EOT
  type = list(object({
    vpc_id     = string
    vpc_region = string
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
