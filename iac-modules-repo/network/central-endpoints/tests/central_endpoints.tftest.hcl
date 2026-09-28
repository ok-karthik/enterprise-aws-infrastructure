# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_resource "aws_vpc_endpoint" {
    defaults = {
      dns_entry = [{ dns_name = "vpce-mock.eu-central-1.vpce.amazonaws.com", hosted_zone_id = "Z00000000000000000" }]
    }
  }

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id = "Z11111111111111111"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-central-1:333344445555:log-group:/aws/vpc/central-endpoints-flow-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::333344445555:role/central-endpoints-flow-log"
    }
  }
}

variables {
  vpc_cidr            = "172.20.0.0/24"
  azs                 = ["eu-central-1a", "eu-central-1b"]
  allowed_cidr_blocks = ["10.0.0.0/8"]
}

run "one_endpoint_and_one_zone_per_default_service" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_endpoint.this)) == toset(["ecr_api", "ecr_dkr", "sts", "ssm", "ssmmessages", "ec2messages", "logs", "kms", "secretsmanager", "eks"])
    error_message = "All ten default services must get an endpoint."
  }

  assert {
    condition     = toset(keys(aws_route53_zone.this)) == toset(keys(aws_vpc_endpoint.this))
    error_message = "Every endpoint must get a matching private hosted zone."
  }
}

run "endpoints_have_dns_managed_by_the_shared_zones_not_their_own" {
  command = plan

  assert {
    condition     = alltrue([for k, e in aws_vpc_endpoint.this : !e.private_dns_enabled])
    error_message = "private_dns_enabled must be off: DNS comes from the shared zones, which resolve in every associated VPC, not just this one."
  }
}

run "security_group_only_allows_https_from_the_given_cidrs" {
  command = plan

  assert {
    condition     = toset([for k, r in aws_vpc_security_group_ingress_rule.https : r.cidr_ipv4]) == toset(var.allowed_cidr_blocks)
    error_message = "Ingress must be scoped to the given CIDR blocks."
  }

  assert {
    condition     = alltrue([for k, r in aws_vpc_security_group_ingress_rule.https : r.from_port == 443 && r.to_port == 443])
    error_message = "Only 443 must be allowed."
  }
}

run "zone_alias_points_at_the_endpoints_regional_dns_name" {
  # apply, not plan: aws_route53_record.alias is Optional+Computed.
  command = apply

  assert {
    condition     = alltrue([for k, r in aws_route53_record.this : r.alias[0].name == "vpce-mock.eu-central-1.vpce.amazonaws.com"])
    error_message = "Every zone's alias record must point at its endpoint's dns_entry[0]."
  }
}

run "no_spoke_authorization_without_spoke_vpcs" {
  command = plan

  assert {
    condition     = length(aws_route53_vpc_association_authorization.spokes) == 0
    error_message = "With no spoke_vpcs (the default), nothing is authorized."
  }
}

run "each_spoke_is_authorized_for_every_service_zone" {
  command = plan

  variables {
    services = ["sts", "ssm"]
    spoke_vpcs = [
      { vpc_id = "vpc-spokedev0000000", vpc_region = "eu-central-1" },
      { vpc_id = "vpc-spokeprod000000", vpc_region = "eu-central-1" },
    ]
  }

  assert {
    condition     = length(aws_route53_vpc_association_authorization.spokes) == 4
    error_message = "2 services x 2 spokes = 4 authorizations."
  }
}

run "unknown_service_is_rejected" {
  command = plan

  variables {
    services = ["rds"]
  }

  expect_failures = [var.services]
}
