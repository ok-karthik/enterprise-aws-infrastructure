variable "role" {
  description = "Which side of the peering this application is: \"requester\" creates the peering attachment, \"accepter\" accepts it."
  type        = string

  validation {
    condition     = contains(["requester", "accepter"], var.role)
    error_message = "role must be requester or accepter."
  }
}

# ------------------------------------------------------------------------------
# Requester inputs
# ------------------------------------------------------------------------------
variable "transit_gateway_id" {
  description = "Requester only: ID of this region's transit gateway (the peering attachment is created FROM it)."
  type        = string
  default     = null

  validation {
    condition     = var.role != "requester" || var.transit_gateway_id != null
    error_message = "role = \"requester\" needs transit_gateway_id."
  }
}

variable "peer_transit_gateway_id" {
  description = "Requester only: ID of the other region's transit gateway (the peering attachment goes TO it)."
  type        = string
  default     = null

  validation {
    condition     = var.role != "requester" || var.peer_transit_gateway_id != null
    error_message = "role = \"requester\" needs peer_transit_gateway_id."
  }
}

variable "peer_region" {
  description = "Requester only: region of the peer transit gateway."
  type        = string
  default     = null

  validation {
    condition     = var.role != "requester" || var.peer_region != null
    error_message = "role = \"requester\" needs peer_region."
  }
}

variable "peer_account_id" {
  description = "Requester only: account that owns the peer transit gateway. Defaults to the caller's account (same-account peering, which is what a single network-hub account needs)."
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Accepter input
# ------------------------------------------------------------------------------
variable "peering_attachment_id" {
  description = "Accepter only: ID of the peering attachment to accept (the requester's peering_attachment_id output, passed in through a Terragrunt dependency)."
  type        = string
  default     = null

  validation {
    condition     = var.role != "accepter" || var.peering_attachment_id != null
    error_message = "role = \"accepter\" needs peering_attachment_id."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
