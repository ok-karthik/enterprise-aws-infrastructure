# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_route53_resolver_rule" {
    defaults = {
      arn = "arn:aws:route53resolver:eu-central-1:333344445555:resolver-rule/rslvr-rr-0123456789abcdef0"
    }
  }

  mock_resource "aws_route53_resolver_query_log_config" {
    defaults = {
      arn = "arn:aws:route53resolver:eu-central-1:333344445555:resolver-query-log-config/rqlc-0123456789abcdef0"
    }
  }

  mock_resource "aws_ram_resource_share" {
    defaults = {
      arn = "arn:aws:ram:eu-central-1:333344445555:resource-share/dns-resolver"
    }
  }

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id      = "Z11111111111111111"
      name_servers = ["ns-1.awsdns-00.org", "ns-2.awsdns-00.co.uk", "ns-3.awsdns-00.com", "ns-4.awsdns-00.net"]
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::333344445555:role/dns-flow-log"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-central-1:333344445555:log-group:/aws/vpc/dns-flow-logs"
    }
  }
}

variables {
  vpc_cidr                  = "172.16.32.0/24"
  azs                       = ["eu-central-1a", "eu-central-1b"]
  workloads_ou_arn          = "arn:aws:organizations::111122223333:ou/o-abcde12345/ou-root-cccccccc"
  query_log_destination_arn = "arn:aws:s3:::platform-vpc-flow-logs-222233334444-eu-central-1/dns/"
}

run "inbound_and_outbound_endpoints_span_every_az" {
  # apply, not plan: ip_address set members have Optional+Computed attributes (ip, ip_id).
  command = apply

  assert {
    condition     = aws_route53_resolver_endpoint.inbound.direction == "INBOUND" && aws_route53_resolver_endpoint.outbound.direction == "OUTBOUND"
    error_message = "One endpoint of each direction must exist."
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.inbound.ip_address) == 2 && length(aws_route53_resolver_endpoint.outbound.ip_address) == 2
    error_message = "Both endpoints must span every given AZ."
  }
}

run "no_forwarding_rules_by_default" {
  command = plan

  assert {
    condition     = length(aws_route53_resolver_rule.forwarding) == 0
    error_message = "With no forwarding_rules (the default), nothing is created."
  }
}

run "a_forwarding_rule_is_created_per_domain_and_shared" {
  command = plan

  variables {
    forwarding_rules = {
      "corp.example.internal" = ["10.50.0.10", "10.50.0.11"]
    }
  }

  assert {
    condition     = aws_route53_resolver_rule.forwarding["corp.example.internal"].domain_name == "corp.example.internal"
    error_message = "The rule must forward the given domain."
  }

  assert {
    condition     = length(aws_route53_resolver_rule.forwarding["corp.example.internal"].target_ip) == 2
    error_message = "Both on-prem DNS server IPs must be targets."
  }

  assert {
    condition     = length(aws_ram_resource_association.rules) == 1
    error_message = "The rule must be RAM-shared."
  }
}

run "query_log_config_is_shared_and_associated_with_this_vpc" {
  command = plan

  assert {
    condition     = aws_route53_resolver_query_log_config.this.destination_arn == var.query_log_destination_arn
    error_message = "Query logs must go to the given destination."
  }

  assert {
    condition     = aws_route53_resolver_query_log_config_association.this.resource_id == aws_vpc.this.id
    error_message = "The query log config must be associated with this module's own VPC."
  }
}

run "no_public_zones_by_default" {
  command = plan

  assert {
    condition     = length(aws_route53_zone.root) == 0
    error_message = "With root_domain empty (the default), no public zone is created."
  }

  assert {
    condition     = output.root_zone_id == null
    error_message = "The output must be null when root_domain is empty."
  }
}

run "delegated_subdomains_get_their_own_zone_and_an_ns_delegation_record" {
  command = plan

  variables {
    root_domain          = "platform.example.com"
    delegated_subdomains = { "workloads-dev" = "dev" }
  }

  assert {
    condition     = one(values(aws_route53_zone.delegated)).name == "dev.platform.example.com"
    error_message = "The delegated zone name must be <label>.<root_domain>."
  }

  assert {
    condition     = one(values(aws_route53_record.delegation)).type == "NS" && one(values(aws_route53_record.delegation)).name == "dev.platform.example.com"
    error_message = "An NS delegation record must exist in the root zone for the subdomain."
  }
}

run "delegated_subdomains_without_a_root_domain_is_rejected" {
  command = plan

  variables {
    delegated_subdomains = { "workloads-dev" = "dev" }
  }

  expect_failures = [var.delegated_subdomains]
}

run "less_than_two_azs_is_rejected" {
  command = plan

  variables {
    azs = ["eu-central-1a"]
  }

  expect_failures = [var.azs]
}

run "bad_workloads_ou_arn_is_rejected" {
  command = plan

  variables {
    workloads_ou_arn = "arn:aws:iam::111122223333:role/not-an-ou"
  }

  expect_failures = [var.workloads_ou_arn]
}
