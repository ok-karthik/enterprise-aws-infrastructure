# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_resource "aws_oam_sink" {
    defaults = {
      arn = "arn:aws:oam:eu-central-1:111122223333:sink/0123abcd-4567-89ef-0123-456789abcdef"
    }
  }
}

run "sink_only_lets_the_organization_link" {
  command = plan

  variables {
    mode            = "sink"
    organization_id = "o-abcde12345"
  }

  assert {
    condition     = length(aws_oam_sink.this) == 1 && length(aws_oam_link.this) == 0 && length(aws_prometheus_workspace.this) == 0
    error_message = "sink mode creates the sink, no link, and no Prometheus by default."
  }

  assert {
    condition     = strcontains(aws_oam_sink_policy.this[0].policy, "o-abcde12345") && strcontains(aws_oam_sink_policy.this[0].policy, "aws:PrincipalOrgID")
    error_message = "The sink policy must be restricted to the organization."
  }
}

run "sink_with_prometheus" {
  command = plan

  variables {
    mode              = "sink"
    organization_id   = "o-abcde12345"
    enable_prometheus = true
  }

  assert {
    condition     = length(aws_prometheus_workspace.this) == 1
    error_message = "enable_prometheus creates the workspace."
  }
}

run "link_sends_metrics_and_logs_to_the_sink" {
  command = plan

  variables {
    mode     = "link"
    sink_arn = "arn:aws:oam:eu-central-1:111122223333:sink/0123abcd-4567-89ef-0123-456789abcdef"
  }

  assert {
    condition     = length(aws_oam_link.this) == 1 && length(aws_oam_sink.this) == 0 && contains(aws_oam_link.this[0].resource_types, "AWS::CloudWatch::Metric") && contains(aws_oam_link.this[0].resource_types, "AWS::Logs::LogGroup")
    error_message = "link mode shares metrics and logs and creates no sink."
  }
}

run "sink_refuses_the_placeholder_organization" {
  command = plan

  variables {
    mode            = "sink"
    organization_id = "o-0000000000"
  }

  expect_failures = [var.organization_id]
}

run "link_needs_a_sink_arn" {
  command = plan

  variables {
    mode = "link"
  }

  expect_failures = [var.sink_arn]
}

run "unknown_resource_type_is_rejected" {
  command = plan

  variables {
    mode            = "sink"
    organization_id = "o-abcde12345"
    resource_types  = ["AWS::S3::Bucket"]
  }

  expect_failures = [var.resource_types]
}
