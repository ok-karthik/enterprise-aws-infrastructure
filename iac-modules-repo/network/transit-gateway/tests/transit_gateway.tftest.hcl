# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_ec2_transit_gateway" {
    defaults = {
      id  = "tgw-0123456789abcdef0"
      arn = "arn:aws:ec2:eu-central-1:333344445555:transit-gateway/tgw-0123456789abcdef0"
    }
  }

  mock_resource "aws_ram_resource_share" {
    defaults = {
      arn = "arn:aws:ram:eu-central-1:333344445555:resource-share/transit-gateway"
    }
  }

  mock_data "aws_ec2_transit_gateway_vpc_attachments" {
    defaults = {
      ids = []
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "333344445555"
    }
  }
}

variables {
  workloads_ou_arn      = "arn:aws:organizations::111122223333:ou/o-abcde12345/ou-root-cccccccc"
  infrastructure_ou_arn = "arn:aws:organizations::111122223333:ou/o-abcde12345/ou-root-dddddddd"
}

run "default_route_association_and_propagation_are_off" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.default_route_table_association == "disable" && aws_ec2_transit_gateway.this.default_route_table_propagation == "disable"
    error_message = "Both defaults must be off: route tables are managed explicitly per spoke."
  }
}

run "four_route_tables_exist" {
  command = plan

  assert {
    condition     = toset(keys(aws_ec2_transit_gateway_route_table.this)) == toset(["prod", "nonprod", "shared", "inspection"])
    error_message = "Exactly prod, nonprod, shared and inspection route tables must exist."
  }
}

run "the_transit_gateway_itself_is_shared_with_both_ous" {
  # apply, not plan: aws_ram_resource_association.resource_arn is Optional+Computed.
  command = apply

  assert {
    condition     = aws_ram_resource_association.this.resource_arn == aws_ec2_transit_gateway.this.arn
    error_message = "The transit gateway resource itself (not a route table) must be RAM-shared."
  }

  assert {
    condition     = toset([aws_ram_principal_association.workloads_ou.principal, aws_ram_principal_association.infrastructure_ou.principal]) == toset([var.workloads_ou_arn, var.infrastructure_ou_arn])
    error_message = "Both the Workloads and Infrastructure OUs must be principals on the share."
  }
}

run "auto_accept_and_explicit_accept_are_both_off_by_default" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.auto_accept_shared_attachments == "disable"
    error_message = "auto_accept_shared_attachments must default to off."
  }

  assert {
    condition     = length(data.aws_ec2_transit_gateway_vpc_attachments.pending) == 0
    error_message = "accept_vpc_attachments must default to off too: on a first apply the transit gateway does not exist yet, so this data source cannot resolve."
  }
}

run "accept_vpc_attachments_can_be_turned_on_once_the_transit_gateway_exists" {
  command = apply

  variables {
    accept_vpc_attachments = true
  }

  assert {
    condition     = length(data.aws_ec2_transit_gateway_vpc_attachments.pending) == 1
    error_message = "Once the transit gateway id is known (apply, or a later plan against existing state), the discovery data source must run."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment_accepter.this) == 0
    error_message = "With no pending attachments, nothing is accepted."
  }
}

run "no_peering_by_default" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_peering_attachment.this) == 0 && length(aws_ec2_transit_gateway_peering_attachment_accepter.this) == 0
    error_message = "peering.role defaults to none: neither side is created."
  }
}

run "requester_peering_needs_a_peer_tgw_and_region" {
  command = plan

  variables {
    peering = {
      role                    = "requester"
      peer_transit_gateway_id = "tgw-9999999999999999"
      peer_region             = "eu-west-1"
    }
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment.this).peer_transit_gateway_id == "tgw-9999999999999999"
    error_message = "The requester attachment must target the given peer transit gateway."
  }
}

run "requester_peering_without_a_peer_region_is_rejected" {
  command = plan

  variables {
    peering = {
      role                    = "requester"
      peer_transit_gateway_id = "tgw-9999999999999999"
    }
  }

  expect_failures = [var.peering]
}

run "accepter_peering_needs_an_attachment_id" {
  command = plan

  variables {
    peering = { role = "accepter" }
  }

  expect_failures = [var.peering]
}

run "accepter_peering_works_with_an_attachment_id" {
  command = plan

  variables {
    peering = { role = "accepter", accepter_attachment_id = "tgw-attach-0123456789abcdef0" }
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment_accepter.this).transit_gateway_attachment_id == "tgw-attach-0123456789abcdef0"
    error_message = "The accepter must accept the given attachment id."
  }
}

run "hybrid_connectivity_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_customer_gateway.this) == 0 && length(aws_vpn_connection.this) == 0 && length(aws_dx_gateway_association.this) == 0
    error_message = "VPN and Direct Connect are opt-in (PLAN 5.6): off by default."
  }
}

run "site_to_site_vpn_needs_a_real_looking_customer_gateway_ip" {
  command = plan

  variables {
    enable_site_to_site_vpn = true
    customer_gateway_ip     = "not-an-ip"
  }

  expect_failures = [var.customer_gateway_ip]
}

run "site_to_site_vpn_can_be_enabled" {
  command = plan

  variables {
    enable_site_to_site_vpn = true
    customer_gateway_ip     = "203.0.113.10"
  }

  assert {
    condition     = one(aws_customer_gateway.this).ip_address == "203.0.113.10"
    error_message = "The customer gateway must use the given IP."
  }

  assert {
    condition     = one(aws_vpn_connection.this).transit_gateway_id == aws_ec2_transit_gateway.this.id
    error_message = "The VPN connection must attach to the transit gateway (not a VPN gateway)."
  }
}

run "direct_connect_association_needs_a_gateway_id" {
  command = plan

  variables {
    enable_direct_connect_gateway_association = true
  }

  expect_failures = [var.direct_connect_gateway_id]
}
