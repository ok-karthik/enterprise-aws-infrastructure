# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  zone_id     = "Z0123456789ABCDEFGHIJ"
  record_name = "api.example.com"
  primary     = { dns_name = "primary-alb.eu-central-1.elb.amazonaws.com", zone_id = "Z215JYRZR1TBD5" }
  secondary   = { dns_name = "dr-alb.eu-west-1.elb.amazonaws.com", zone_id = "Z32O12XQLNTSW2" }
  health_check = {
    fqdn = "primary-alb.eu-central-1.elb.amazonaws.com"
  }
}

run "primary_is_health_checked_and_secondary_is_not" {
  command = plan

  assert {
    condition     = one(aws_route53_record.primary.failover_routing_policy).type == "PRIMARY" && one(aws_route53_record.secondary.failover_routing_policy).type == "SECONDARY"
    error_message = "One PRIMARY and one SECONDARY record."
  }

  assert {
    condition     = aws_route53_record.secondary.health_check_id == null
    error_message = "The secondary has no health check: it is the last resort and must always answer."
  }
}

run "defaults_detect_failure_in_90_seconds" {
  command = plan

  assert {
    condition     = aws_route53_health_check.primary.failure_threshold * aws_route53_health_check.primary.request_interval == 90
    error_message = "Default detection time should be 3 x 30 s."
  }
}

run "bad_interval_is_rejected" {
  command = plan

  variables {
    health_check = {
      fqdn             = "x.example.com"
      request_interval = 20
    }
  }

  expect_failures = [var.health_check]
}

run "bad_zone_id_is_rejected" {
  command = plan

  variables {
    zone_id = "nope"
  }

  expect_failures = [var.zone_id]
}
