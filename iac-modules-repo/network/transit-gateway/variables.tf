variable "amazon_side_asn" {
  description = "BGP ASN on the Amazon side of the transit gateway (used for VPN/Direct Connect BGP sessions)."
  type        = number
  default     = 64512

  validation {
    condition     = var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534
    error_message = "amazon_side_asn must be a private-use 16-bit ASN (64512-65534)."
  }
}

variable "workloads_ou_arn" {
  description = "ARN of the Workloads OU. The transit gateway itself (not its route tables) is shared with this OU and infrastructure_ou_arn through RAM, so spoke accounts can attach to it."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:organizations::[0-9]{12}:ou/o-[a-z0-9]+/ou-", var.workloads_ou_arn))
    error_message = "workloads_ou_arn must be an Organizations OU ARN."
  }
}

variable "infrastructure_ou_arn" {
  description = "ARN of the Infrastructure OU. Shared the same way as workloads_ou_arn."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:organizations::[0-9]{12}:ou/o-[a-z0-9]+/ou-", var.infrastructure_ou_arn))
    error_message = "infrastructure_ou_arn must be an Organizations OU ARN."
  }
}

variable "accept_vpc_attachments" {
  description = <<-EOT
    Discover and accept pending VPC attachments from spoke accounts (RAM-shared, so only principals in
    workloads_ou_arn / infrastructure_ou_arn could ever create one). The transit gateway itself defaults to
    NOT auto-accepting (var.auto_accept_shared_attachments), so this explicit, reviewable accept step in
    network-hub is what actually attaches a spoke -- matching PLAN 5.2's "the acceptance side is in
    network-hub". Off by default and turned on in a LATER apply, never the transit gateway's first one: on
    a first apply the transit gateway does not exist yet, so a for_each built from a data source that reads
    it cannot resolve (a real Terraform limitation, not just a mock artifact). Turn it on once the transit
    gateway exists and a spoke has actually requested an attachment.
  EOT
  type        = bool
  default     = false
}

variable "auto_accept_shared_attachments" {
  description = "Whether the transit gateway itself auto-accepts a RAM-shared attachment request. Off by default: var.accept_vpc_attachments is the explicit, reviewable path instead."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Cross-region peering (this module is applied once per region; the two applications coordinate through
# these variables -- one is the requester, the other the accepter).
# ------------------------------------------------------------------------------
variable "peering" {
  description = <<-EOT
    Cross-region peering to another region's transit gateway (PLAN 5.2, primary_region <-> secondary_region).
    role = "none" (default): no peering attachment from this region.
    role = "requester": creates the peering attachment FROM this region's transit gateway TO
      peer_transit_gateway_id in peer_region (peer_account_id defaults to this account, i.e. same-account
      peering, which is what a single network-hub account needs).
    role = "accepter": accepts a peering attachment created by the OTHER region's requester
      (accepter_attachment_id -- that region's module output peering_attachment_id, passed in through a
      Terragrunt dependency).
  EOT
  type = object({
    role                    = optional(string, "none")
    peer_transit_gateway_id = optional(string)
    peer_region             = optional(string)
    peer_account_id         = optional(string)
    accepter_attachment_id  = optional(string)
  })
  default = {}

  validation {
    condition     = contains(["none", "requester", "accepter"], var.peering.role)
    error_message = "peering.role must be none, requester or accepter."
  }

  validation {
    condition     = var.peering.role != "requester" || (var.peering.peer_transit_gateway_id != null && var.peering.peer_region != null)
    error_message = "peering.role = \"requester\" needs peer_transit_gateway_id and peer_region."
  }

  validation {
    condition     = var.peering.role != "accepter" || var.peering.accepter_attachment_id != null
    error_message = "peering.role = \"accepter\" needs accepter_attachment_id."
  }
}

# ------------------------------------------------------------------------------
# Hybrid connectivity (PLAN 5.6): optional flags. Module and docs only -- there is no real peer to connect to.
# ------------------------------------------------------------------------------
variable "enable_site_to_site_vpn" {
  description = "Create a Customer Gateway and a Site-to-Site VPN connection attached to the transit gateway. Off by default: needs a real customer_gateway_ip."
  type        = bool
  default     = false
}

variable "customer_gateway_ip" {
  description = "Public IP of the on-premises VPN device. Required when enable_site_to_site_vpn is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_site_to_site_vpn || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.customer_gateway_ip))
    error_message = "customer_gateway_ip must be a real IPv4 address when enable_site_to_site_vpn is true."
  }
}

variable "customer_gateway_bgp_asn" {
  description = "BGP ASN of the on-premises VPN device."
  type        = number
  default     = 65000
}

variable "enable_direct_connect_gateway_association" {
  description = "Associate a Direct Connect gateway with the transit gateway. Off by default: needs a real direct_connect_gateway_id."
  type        = bool
  default     = false
}

variable "direct_connect_gateway_id" {
  description = "ID of an existing Direct Connect gateway. Required when enable_direct_connect_gateway_association is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_direct_connect_gateway_association || var.direct_connect_gateway_id != ""
    error_message = "direct_connect_gateway_id must be set when enable_direct_connect_gateway_association is true."
  }
}

variable "direct_connect_gateway_allowed_prefixes" {
  description = "CIDR blocks the Direct Connect gateway may advertise to the transit gateway."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
