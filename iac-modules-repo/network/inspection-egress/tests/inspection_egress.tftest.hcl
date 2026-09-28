# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "333344445555"
    }
  }

  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-inspection0123456789"
    }
  }

  mock_resource "aws_networkfirewall_rule_group" {
    defaults = {
      arn = "arn:aws:network-firewall:eu-central-1:333344445555:stateful-rulegroup/rule-group"
    }
  }

  mock_resource "aws_networkfirewall_firewall_policy" {
    defaults = {
      arn = "arn:aws:network-firewall:eu-central-1:333344445555:firewall-policy/inspection-egress-policy"
    }
  }

  mock_resource "aws_networkfirewall_firewall" {
    defaults = {
      arn = "arn:aws:network-firewall:eu-central-1:333344445555:firewall/inspection-egress"
      firewall_status = [{
        sync_states = [
          { availability_zone = "eu-central-1a", attachment = [{ endpoint_id = "vpce-aaaa", subnet_id = "subnet-fw-a" }], transit_gateway_attachment_sync_states = [] },
          { availability_zone = "eu-central-1b", attachment = [{ endpoint_id = "vpce-bbbb", subnet_id = "subnet-fw-b" }], transit_gateway_attachment_sync_states = [] },
        ]
      }]
    }
  }
}

variables {
  vpc_cidr                  = "10.99.0.0/20"
  azs                       = ["eu-central-1a", "eu-central-1b"]
  transit_gateway_id        = "tgw-0123456789abcdef0"
  inspection_route_table_id = "tgw-rtb-0123456789abcdef0"
  domain_allow_list         = ["pypi.org", "github.com"]
  log_archive_bucket_name   = "platform-vpc-flow-logs-222233334444-eu-central-1"
}

run "three_subnet_tiers_per_az" {
  command = plan

  assert {
    condition     = toset(keys(aws_subnet.tgw)) == toset(var.azs) && toset(keys(aws_subnet.firewall)) == toset(var.azs) && toset(keys(aws_subnet.public)) == toset(var.azs)
    error_message = "Every AZ must get a tgw, a firewall and a public subnet."
  }

  assert {
    condition     = length(distinct(concat([for s in aws_subnet.tgw : s.cidr_block], [for s in aws_subnet.firewall : s.cidr_block], [for s in aws_subnet.public : s.cidr_block]))) == 6
    error_message = "All 6 subnet CIDRs (2 AZs x 3 tiers) must be distinct."
  }
}

run "one_nat_gateway_per_az" {
  command = plan

  assert {
    condition     = toset(keys(aws_nat_gateway.this)) == toset(var.azs)
    error_message = "Every AZ must get its own NAT gateway."
  }
}

run "firewall_policy_is_strict_order_drop_by_default" {
  command = plan

  assert {
    condition     = toset(one(aws_networkfirewall_firewall_policy.this.firewall_policy).stateful_default_actions) == toset(["aws:drop_established"])
    error_message = "Anything not explicitly allowed must be dropped once established (an allow-list, not a deny-list)."
  }

  assert {
    condition     = one(one(aws_networkfirewall_firewall_policy.this.firewall_policy).stateful_engine_options).rule_order == "STRICT_ORDER"
    error_message = "The rule order must be strict, so the allow-list rule group is actually authoritative."
  }
}

run "domain_allow_list_rule_group_uses_the_given_domains" {
  command = plan

  assert {
    condition     = one(one(one(aws_networkfirewall_rule_group.domain_allow_list.rule_group).rules_source).rules_source_list).generated_rules_type == "ALLOWLIST"
    error_message = "The rule group must be an ALLOWLIST, not a DENYLIST."
  }

  assert {
    condition     = toset(one(one(one(aws_networkfirewall_rule_group.domain_allow_list.rule_group).rules_source).rules_source_list).targets) == toset(var.domain_allow_list)
    error_message = "The rule group must use the given domain list."
  }
}

run "no_additional_rule_group_without_additional_suricata_rules" {
  command = plan

  assert {
    condition     = length(aws_networkfirewall_rule_group.additional) == 0
    error_message = "With no additional_suricata_rules, no second rule group must be created."
  }
}

run "additional_suricata_rules_add_a_second_rule_group" {
  # apply, not plan: stateful_rule_group_reference members have Optional+Computed attributes.
  command = apply

  variables {
    additional_suricata_rules = "alert tcp any any -> any any (msg:\"test\"; sid:1;)"
  }

  assert {
    condition     = length(aws_networkfirewall_rule_group.additional) == 1
    error_message = "additional_suricata_rules must create a second rule group."
  }

  assert {
    condition     = length(one(aws_networkfirewall_firewall_policy.this.firewall_policy).stateful_rule_group_reference) == 2
    error_message = "The firewall policy must reference both rule groups."
  }
}

run "logging_goes_to_the_given_log_archive_bucket" {
  command = plan

  assert {
    condition = alltrue([
      for c in one(aws_networkfirewall_logging_configuration.this.logging_configuration).log_destination_config :
      c.log_destination["bucketName"] == var.log_archive_bucket_name
    ])
    error_message = "Both log types must go to the given log-archive bucket."
  }

  assert {
    condition     = toset([for c in one(aws_networkfirewall_logging_configuration.this.logging_configuration).log_destination_config : c.log_type]) == toset(["ALERT", "FLOW"])
    error_message = "Both ALERT and FLOW logs must be configured."
  }
}

run "attachment_uses_appliance_mode_and_the_inspection_route_table" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.this.appliance_mode_support == "enable"
    error_message = "Appliance mode must be on: a flow must keep using the same firewall endpoint."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.this.transit_gateway_route_table_id == var.inspection_route_table_id
    error_message = "The attachment must associate into the inspection route table."
  }
}

run "empty_domain_allow_list_is_rejected" {
  command = plan

  variables {
    domain_allow_list = []
  }

  expect_failures = [var.domain_allow_list]
}
