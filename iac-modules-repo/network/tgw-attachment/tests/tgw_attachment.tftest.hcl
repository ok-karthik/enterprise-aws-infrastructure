# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_ec2_transit_gateway_vpc_attachment" {
    defaults = {
      id = "tgw-attach-0123456789abcdef0"
    }
  }
}

variables {
  transit_gateway_id = "tgw-0123456789abcdef0"
  vpc_id             = "vpc-0123456789abcdef0"
  subnet_ids         = ["subnet-aaaa", "subnet-bbbb"]
  route_table_id     = "tgw-rtb-0123456789abcdef0"
}

run "attachment_does_not_manage_the_default_route_tables" {
  command = plan

  assert {
    condition     = !aws_ec2_transit_gateway_vpc_attachment.this.transit_gateway_default_route_table_association && !aws_ec2_transit_gateway_vpc_attachment.this.transit_gateway_default_route_table_propagation
    error_message = "The attachment must not use the transit gateway's default route table association/propagation: only the given route_table_id."
  }
}

run "association_and_propagation_target_the_given_route_table" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.this.transit_gateway_route_table_id == "tgw-rtb-0123456789abcdef0"
    error_message = "The association must target the given route table."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route_table_propagation.this.transit_gateway_route_table_id == "tgw-rtb-0123456789abcdef0"
    error_message = "The propagation must target the given route table."
  }
}

run "no_egress_route_by_default" {
  command = plan

  assert {
    condition     = length(aws_route.egress_via_tgw) == 0
    error_message = "With egress_route_cidr empty (the default), no route is added."
  }
}

run "central_egress_adds_a_route_in_every_given_table" {
  command = plan

  variables {
    egress_route_cidr       = "0.0.0.0/0"
    private_route_table_ids = ["rtb-aaaa", "rtb-bbbb"]
  }

  assert {
    condition     = toset(keys(aws_route.egress_via_tgw)) == toset(["rtb-aaaa", "rtb-bbbb"])
    error_message = "A route must be added to every given private route table."
  }

  assert {
    condition     = aws_route.egress_via_tgw["rtb-aaaa"].transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "The route must point at the transit gateway."
  }
}

run "egress_route_cidr_without_route_tables_is_rejected" {
  command = plan

  variables {
    egress_route_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.private_route_table_ids]
}

run "empty_subnet_ids_is_rejected" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}
