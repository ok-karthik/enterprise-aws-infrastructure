variable "transit_gateway_id" {
  description = "ID of the transit gateway to attach to (network/transit-gateway's output, from the network-hub account, RAM-shared with this account's OU)."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to attach."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs the attachment uses (one per AZ; usually the private subnets). At least one is required, and one per AZ is recommended for resilience."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must not be empty."
  }
}

variable "route_table_id" {
  description = "Transit gateway route table to associate and propagate this attachment into (network/transit-gateway's route_table_ids[\"prod\"] or [\"nonprod\"], never both -- prod and nonprod cannot route to each other, PLAN 5.2)."
  type        = string
}

variable "appliance_mode_support" {
  description = "Enable appliance mode (keeps a flow pinned to one AZ's route, needed for a stateful appliance like the inspection VPC's firewall, PLAN 5.3). Off for an ordinary spoke VPC."
  type        = bool
  default     = false
}

variable "egress_route_cidr" {
  description = "Destination CIDR to add to THIS VPC's own route tables pointing at the transit gateway, e.g. \"0.0.0.0/0\" for central egress (network/vpc's egress_mode = \"central\", PLAN 5.3). Empty adds no route here (the caller manages its own routes, or uses egress_mode = \"local-nat\")."
  type        = string
  default     = ""
}

variable "private_route_table_ids" {
  description = "This VPC's own private route table IDs, to add egress_route_cidr to. Required when egress_route_cidr is set."
  type        = list(string)
  default     = []

  validation {
    condition     = var.egress_route_cidr == "" || length(var.private_route_table_ids) > 0
    error_message = "private_route_table_ids must be set when egress_route_cidr is set."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
