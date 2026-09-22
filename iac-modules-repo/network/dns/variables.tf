variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "dns"
}

variable "vpc_cidr" {
  description = "CIDR for this module's own small VPC (the resolver endpoints need ENIs somewhere)."
  type        = string
}

variable "azs" {
  description = "Availability zones for the resolver endpoint subnets (at least two, AWS's own minimum)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "azs needs at least two AZs (a Resolver endpoint requires it)."
  }
}

variable "on_prem_cidr_blocks" {
  description = "CIDR blocks allowed to query the inbound resolver endpoint (on-premises networks, reached over the hybrid connectivity in network/transit-gateway, PLAN 5.6)."
  type        = list(string)
  default     = []
}

variable "forwarding_rules" {
  description = "domain_name => list of on-premises DNS server IPs to forward that domain to (a FORWARD resolver rule per entry, shared with workloads_ou_arn through RAM)."
  type        = map(list(string))
  default     = {}
}

variable "workloads_ou_arn" {
  description = "ARN of the Workloads OU. Forwarding rules and the query log config are shared with this OU through RAM."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:organizations::[0-9]{12}:ou/o-[a-z0-9]+/ou-", var.workloads_ou_arn))
    error_message = "workloads_ou_arn must be an Organizations OU ARN."
  }
}

variable "query_log_destination_arn" {
  description = "Where resolver query logs go: an S3 bucket ARN (security/log-archive's vpc_flow_logs bucket, the same one network/inspection-egress uses) or a CloudWatch Logs group ARN."
  type        = string
}

variable "root_domain" {
  description = "The platform's public root domain, hosted in network-hub. Empty (the default) creates no public zone."
  type        = string
  default     = ""
}

variable "delegated_subdomains" {
  description = <<-EOT
    workload account name => subdomain label (e.g. { "workloads-dev" = "dev" } for dev.<root_domain>). Each
    gets its OWN public hosted zone here, plus an NS delegation record in the root zone. The workload account
    is expected to use that zone's name servers for its own subdomain records (not built here: the workload
    account needs its own aws_route53_zone matching, or a data source reading this zone's id, depending on
    who is meant to own records in it -- see the module README). Needs root_domain to be set.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.delegated_subdomains) == 0 || var.root_domain != ""
    error_message = "delegated_subdomains needs root_domain to be set (a subdomain delegation needs a parent zone)."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
