variable "zone_id" {
  type        = string
  description = "Route 53 hosted zone that holds the record (from network/dns)"

  validation {
    condition     = can(regex("^Z[A-Z0-9]{5,31}$", var.zone_id))
    error_message = "zone_id must look like a hosted zone ID (Z...)."
  }
}

variable "record_name" {
  type        = string
  description = "Fully qualified name clients use, for example api.example.com"
}

variable "primary" {
  type = object({
    dns_name = string
    zone_id  = string
  })
  description = "Primary endpoint as an alias target (for example the ALB's dns_name and zone_id in eu-central-1)"
}

variable "secondary" {
  type = object({
    dns_name = string
    zone_id  = string
  })
  description = "Secondary (DR) endpoint as an alias target (the ALB in eu-west-1)"
}

variable "health_check" {
  type = object({
    fqdn              = string
    port              = optional(number, 443)
    type              = optional(string, "HTTPS")
    path              = optional(string, "/healthz")
    failure_threshold = optional(number, 3)
    request_interval  = optional(number, 30)
  })
  description = "Health check that decides when traffic leaves the primary. Point fqdn at the primary endpoint itself, not at the failover name."

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.health_check.type) && contains([10, 30], var.health_check.request_interval)
    error_message = "health_check.type must be HTTP or HTTPS and request_interval 10 or 30 seconds."
  }
}

variable "evaluate_target_health" {
  type        = bool
  description = "Also treat an unhealthy alias target (for example an ALB with no healthy targets) as a failure"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags for the health check"
  default     = {}
}
