# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_ec2_transit_gateway_peering_attachment" {
    defaults = {
      id = "tgw-attach-0aaaaaaaaaaaaaaaa"
    }
  }

  mock_resource "aws_ec2_transit_gateway_peering_attachment_accepter" {
    defaults = {
      id = "tgw-attach-0aaaaaaaaaaaaaaaa"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "333344445555"
    }
  }
}

run "role_is_required_to_be_requester_or_accepter" {
  command = plan

  variables {
    role = "none"
  }

  expect_failures = [var.role]
}

run "requester_creates_the_peering_attachment" {
  command = plan

  variables {
    role                    = "requester"
    transit_gateway_id      = "tgw-0123456789abcdef0"
    peer_transit_gateway_id = "tgw-9999999999999999"
    peer_region             = "eu-west-1"
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment.this).transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "The requester attachment must start from the given transit gateway."
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment.this).peer_transit_gateway_id == "tgw-9999999999999999"
    error_message = "The requester attachment must target the given peer transit gateway."
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment.this).peer_account_id == "333344445555"
    error_message = "peer_account_id must default to the caller's account (same-account peering)."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_peering_attachment_accepter.this) == 0
    error_message = "A requester must not create the accepter."
  }
}

run "requester_can_peer_with_another_account" {
  command = plan

  variables {
    role                    = "requester"
    transit_gateway_id      = "tgw-0123456789abcdef0"
    peer_transit_gateway_id = "tgw-9999999999999999"
    peer_region             = "eu-west-1"
    peer_account_id         = "444455556666"
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment.this).peer_account_id == "444455556666"
    error_message = "An explicit peer_account_id must be used."
  }
}

run "requester_without_a_peer_region_is_rejected" {
  command = plan

  variables {
    role                    = "requester"
    transit_gateway_id      = "tgw-0123456789abcdef0"
    peer_transit_gateway_id = "tgw-9999999999999999"
  }

  expect_failures = [var.peer_region]
}

run "requester_without_a_transit_gateway_is_rejected" {
  command = plan

  variables {
    role                    = "requester"
    peer_transit_gateway_id = "tgw-9999999999999999"
    peer_region             = "eu-west-1"
  }

  expect_failures = [var.transit_gateway_id]
}

run "requester_without_a_peer_transit_gateway_is_rejected" {
  command = plan

  variables {
    role               = "requester"
    transit_gateway_id = "tgw-0123456789abcdef0"
    peer_region        = "eu-west-1"
  }

  expect_failures = [var.peer_transit_gateway_id]
}

run "accepter_without_an_attachment_id_is_rejected" {
  command = plan

  variables {
    role = "accepter"
  }

  expect_failures = [var.peering_attachment_id]
}

run "accepter_accepts_the_given_attachment" {
  command = plan

  variables {
    role                  = "accepter"
    peering_attachment_id = "tgw-attach-0123456789abcdef0"
  }

  assert {
    condition     = one(aws_ec2_transit_gateway_peering_attachment_accepter.this).transit_gateway_attachment_id == "tgw-attach-0123456789abcdef0"
    error_message = "The accepter must accept the given attachment id."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_peering_attachment.this) == 0
    error_message = "An accepter must not create a peering attachment."
  }
}
