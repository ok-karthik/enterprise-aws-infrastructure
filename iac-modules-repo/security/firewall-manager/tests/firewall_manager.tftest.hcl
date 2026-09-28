# Tests for security/firewall-manager (PLAN 6.1)

# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}
# These run with `terraform test` using `terraform validate` only (no real AWS calls).

# ---------- defaults ----------
run "defaults" {
  command = plan

  variables {
    admin_account_id  = "222222222222"
    waf_target_ou_ids = ["ou-test-workloads"]
  }

  # WAF policy is created
  assert {
    condition     = aws_fms_policy.waf.name == "platform-waf-policy"
    error_message = "WAF policy name should use the default."
  }

  # Rate-based rule group is created (default rate_limit > 0)
  assert {
    condition     = length(aws_wafv2_rule_group.rate_limit) == 1
    error_message = "Rate-based rule group should be created when rate_limit > 0."
  }

  # SG audit policy is created by default
  assert {
    condition     = length(aws_fms_policy.sg_audit) == 1
    error_message = "SG audit policy should be enabled by default."
  }

  # Network firewall policy disabled by default
  assert {
    condition     = length(aws_fms_policy.network_firewall) == 0
    error_message = "Network Firewall policy should be disabled by default."
  }
}

# ---------- bot control enabled ----------
run "bot_control" {
  command = plan

  variables {
    admin_account_id   = "222222222222"
    waf_target_ou_ids  = ["ou-test-workloads"]
    enable_bot_control = true
    bot_control_action = "COUNT"
  }

  assert {
    condition     = aws_fms_policy.waf.name == "platform-waf-policy"
    error_message = "WAF policy should be created with bot control."
  }
}

# ---------- rate limit disabled ----------
run "no_rate_limit" {
  command = plan

  variables {
    admin_account_id  = "222222222222"
    waf_target_ou_ids = ["ou-test-workloads"]
    rate_limit        = 0
  }

  assert {
    condition     = length(aws_wafv2_rule_group.rate_limit) == 0
    error_message = "Rate-based rule group should not be created when rate_limit is 0."
  }
}

# ---------- network firewall policy ----------
run "with_network_firewall" {
  command = plan

  variables {
    admin_account_id               = "222222222222"
    waf_target_ou_ids              = ["ou-test-workloads"]
    enable_network_firewall_policy = true
    nfw_target_ou_ids              = ["ou-test-workloads"]
    nfw_stateful_rule_group_arns   = ["arn:aws:network-firewall:eu-central-1:222222222222:stateful-rulegroup/test"]
  }

  assert {
    condition     = length(aws_fms_policy.network_firewall) == 1
    error_message = "Network Firewall policy should be created when enabled."
  }
}

# ---------- validation: bad admin account id ----------
run "bad_admin_account_id" {
  command = plan

  variables {
    admin_account_id  = "000000000001"
    waf_target_ou_ids = ["ou-test-workloads"]
  }

  expect_failures = [var.admin_account_id]
}

# ---------- validation: empty OU list ----------
run "empty_waf_ou_ids" {
  command = plan

  variables {
    admin_account_id  = "222222222222"
    waf_target_ou_ids = []
  }

  expect_failures = [var.waf_target_ou_ids]
}
