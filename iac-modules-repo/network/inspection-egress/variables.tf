variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "inspection-egress"
}

variable "vpc_cidr" {
  description = "CIDR for the inspection/egress VPC. Sized for three /AZ subnet tiers (tgw, firewall, public)."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread NAT gateways and firewall endpoints across (one of each per AZ)."
  type        = list(string)

  validation {
    condition     = length(var.azs) > 0
    error_message = "azs must not be empty."
  }
}

variable "transit_gateway_id" {
  description = "ID of the transit gateway to attach to (network/transit-gateway's output), so spoke traffic can reach this VPC."
  type        = string
}

variable "inspection_route_table_id" {
  description = "The transit gateway's \"inspection\" route table id, this attachment associates/propagates into."
  type        = string
}

variable "domain_allow_list" {
  description = "Domains (TLS SNI / HTTP Host) the stateful firewall rule group allows. Traffic to any other domain is dropped -- this is an allow-list, not a deny-list."
  type        = list(string)

  validation {
    condition     = length(var.domain_allow_list) > 0
    error_message = "domain_allow_list must not be empty (an empty allow-list, ALLOWLIST generated_rules_type with zero targets, would deny everything -- if that is really wanted, say so explicitly with one entry and review it)."
  }
}

variable "additional_suricata_rules" {
  description = "Extra stateful rules in raw Suricata format, appended after the domain allow-list rule group. Empty by default."
  type        = string
  default     = ""
}

variable "log_archive_bucket_name" {
  description = "S3 bucket in log-archive to send firewall alert and flow logs to: security/log-archive's bucket_names[\"vpc_flow_logs\"] output (both log types share it; log-archive has no dedicated Network Firewall bucket type)."
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
