variable "organization_id" {
  description = "ID of the AWS Organization (o-xxxxxxxxxx). The pools are shared with the Workloads OU via RAM, which needs organization sharing turned on (aws_ram_sharing_with_organization, applied once per organization elsewhere -- see the module README)."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && !can(regex("^o-0+$", var.organization_id))
    error_message = "organization_id must be a real organization id (o-...), not the 0000 placeholder."
  }
}

variable "workloads_ou_arn" {
  description = "ARN of the Workloads OU (governance/organization's organizational_unit_ids[\"Workloads\"], turned into an OU ARN). The regional pools are shared with this OU."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:organizations::[0-9]{12}:ou/o-[a-z0-9]+/ou-", var.workloads_ou_arn))
    error_message = "workloads_ou_arn must be an Organizations OU ARN (arn:aws:organizations::<management account id>:ou/<org id>/<ou id>)."
  }
}

variable "top_level_cidr" {
  description = "The org-wide IPv4 CIDR the top-level pool is carved from (RFC 1918 space, sized for every account and region this platform will ever use)."
  type        = string
  default     = "10.0.0.0/8"
}

variable "operating_regions" {
  description = "Regions IPAM operates in. Must include every region a regional pool is created for."
  type        = list(string)
  default     = ["eu-central-1", "eu-west-1"]

  validation {
    condition     = length(var.operating_regions) > 0
    error_message = "operating_regions must not be empty."
  }
}

variable "regional_pools" {
  description = <<-EOT
    One entry per region: the locale (region) and the CIDR carved out of top_level_cidr for it. Each regional
    pool gets two child pools, "prod" and "nonprod", splitting the region's space by
    prod_env_netmask_length / nonprod_env_netmask_length.
  EOT
  type = map(object({
    locale = string
    cidr   = string
  }))
  default = {
    eu-central-1 = { locale = "eu-central-1", cidr = "10.0.0.0/9" }
    eu-west-1    = { locale = "eu-west-1", cidr = "10.128.0.0/9" }
  }

  validation {
    condition     = alltrue([for k, v in var.regional_pools : k == v.locale])
    error_message = "Every regional_pools key must equal its own locale (the map key is also used to name resources)."
  }
}

variable "prod_env_netmask_length" {
  description = "Netmask length of each region's prod env pool (a /netmask carved from that region's pool)."
  type        = number
  default     = 10
}

variable "nonprod_env_netmask_length" {
  description = "Netmask length of each region's nonprod env pool."
  type        = number
  default     = 10
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
