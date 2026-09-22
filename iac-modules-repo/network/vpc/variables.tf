variable "name" {
  description = "Name to be used on all resources as prefix"
  type        = string
}

variable "cidr" {
  description = "The CIDR block for the VPC. Exactly one of cidr or (ipv4_ipam_pool_id + ipv4_netmask_length) must be set (PLAN 5.1)."
  type        = string
  default     = ""

  validation {
    condition = (
      (var.cidr != "" && var.ipv4_ipam_pool_id == "" && var.ipv4_netmask_length == null) ||
      (var.cidr == "" && var.ipv4_ipam_pool_id != "" && var.ipv4_netmask_length != null)
    )
    error_message = "Set exactly one of cidr, or both ipv4_ipam_pool_id and ipv4_netmask_length -- never neither, never a mix."
  }
}

variable "ipv4_ipam_pool_id" {
  description = "IPAM pool to request the VPC's CIDR from (network/ipam's env_pool_ids output), instead of a literal cidr. Requires ipv4_netmask_length too."
  type        = string
  default     = ""
}

variable "ipv4_netmask_length" {
  description = "Netmask length to request from ipv4_ipam_pool_id, e.g. 20 for a /20. Requires ipv4_ipam_pool_id too."
  type        = number
  default     = null
}

variable "default_network_acl_allow_cidr" {
  description = <<-EOT
    CIDR the default network ACL allows ingress from. Empty means: use var.cidr when it is set, or
    "10.0.0.0/8" (the platform's whole IPAM address space, network/ipam's default top_level_cidr) when using
    IPAM, because the real allocated CIDR is not known until after the first apply. Set this explicitly (the
    env pool's own range, once you know it) to narrow it back down for an IPAM-sourced VPC.
  EOT
  type        = string
  default     = ""
}

variable "azs" {
  description = "A list of availability zones names or ids in the region"
  type        = list(string)
}

variable "private_subnets" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
}

variable "public_subnets" {
  description = "A list of public subnets inside the VPC"
  type        = list(string)
}

variable "database_subnets" {
  description = "A list of database subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways for each of your private networks"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all of your private networks"
  type        = bool
  default     = true
}

variable "egress_mode" {
  description = <<-EOT
    "local-nat" (default): this VPC's own NAT gateways, controlled by enable_nat_gateway/single_nat_gateway,
    as before. "central" (PLAN 5.3): no NAT gateways here at all, regardless of enable_nat_gateway --
    0.0.0.0/0 goes to the transit gateway instead, through network/tgw-attachment's egress_route_cidr, and
    on to network/inspection-egress in network-hub.
  EOT
  type        = string
  default     = "local-nat"

  validation {
    condition     = contains(["local-nat", "central"], var.egress_mode)
    error_message = "egress_mode must be local-nat or central."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster to tag subnets for"
  type        = string
  default     = ""
}

variable "env" {
  description = "Target environment for naming and discovery contract (e.g. dev, prod)"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region for naming and discovery contract (e.g. eu-central-1)"
  type        = string
  default     = ""
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
