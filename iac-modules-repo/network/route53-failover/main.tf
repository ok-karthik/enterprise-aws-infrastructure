# Failover routing: clients get the primary while its health check passes, otherwise the secondary.
# An alias record has no TTL of its own, so cutover time is the health check detection time
# (request_interval x failure_threshold, 90 s by default) plus resolver caching.

resource "aws_route53_health_check" "primary" {
  fqdn              = var.health_check.fqdn
  port              = var.health_check.port
  type              = var.health_check.type
  resource_path     = var.health_check.path
  failure_threshold = var.health_check.failure_threshold
  request_interval  = var.health_check.request_interval
  measure_latency   = true

  tags = merge({ Name = "${var.record_name}-primary" }, var.tags)
}

resource "aws_route53_record" "primary" {
  #checkov:skip=CKV2_AWS_23: "The alias target is an input (the load balancer lives in another stack), so this stack cannot contain the resource Checkov looks for"
  zone_id        = var.zone_id
  name           = var.record_name
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary.dns_name
    zone_id                = var.primary.zone_id
    evaluate_target_health = var.evaluate_target_health
  }
}

resource "aws_route53_record" "secondary" {
  #checkov:skip=CKV2_AWS_23: "The alias target is an input (the load balancer lives in another stack), so this stack cannot contain the resource Checkov looks for"
  zone_id        = var.zone_id
  name           = var.record_name
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary.dns_name
    zone_id                = var.secondary.zone_id
    evaluate_target_health = var.evaluate_target_health
  }
}
