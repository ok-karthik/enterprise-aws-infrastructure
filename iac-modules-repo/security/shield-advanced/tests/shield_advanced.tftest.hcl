# Tests for security/shield-advanced (PLAN 6.4)

# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

run "disabled_by_default" {
  command = plan

  variables {}

  assert {
    condition     = length(aws_shield_subscription.this) == 0
    error_message = "Shield subscription should not be created when enabled = false."
  }

  assert {
    condition     = length(aws_shield_protection.this) == 0
    error_message = "No protections should be created when disabled."
  }
}

run "enabled_with_protections" {
  command = plan

  variables {
    enabled = true
    protected_resources = {
      "prod-alb" = "arn:aws:elasticloadbalancing:eu-central-1:222222222222:loadbalancer/app/prod-alb/1234567890"
    }
  }

  assert {
    condition     = length(aws_shield_subscription.this) == 1
    error_message = "Shield subscription should be created when enabled."
  }

  assert {
    condition     = length(aws_shield_protection.this) == 1
    error_message = "One protection should be created."
  }
}

run "proactive_engagement" {
  command = plan

  variables {
    enabled                     = true
    enable_proactive_engagement = true
    proactive_engagement_contacts = [
      {
        email_address = "security@example.com"
        phone_number  = "+15555555555"
        note          = "Primary security contact"
      }
    ]
  }

  assert {
    condition     = length(aws_shield_proactive_engagement.this) == 1
    error_message = "Proactive engagement should be created."
  }
}

run "bad_contact_email" {
  command = plan

  variables {
    enabled                     = true
    enable_proactive_engagement = true
    proactive_engagement_contacts = [
      {
        email_address = "not-an-email"
        phone_number  = "+15555555555"
      }
    ]
  }

  expect_failures = [var.proactive_engagement_contacts]
}

run "bad_contact_phone" {
  command = plan

  variables {
    enabled                     = true
    enable_proactive_engagement = true
    proactive_engagement_contacts = [
      {
        email_address = "security@example.com"
        phone_number  = "+1-555-555-5555"
      }
    ]
  }

  expect_failures = [var.proactive_engagement_contacts]
}
