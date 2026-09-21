# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

variables {
  ou_ids = {
    Security = "ou-ab12-11111111"
    NonProd  = "ou-ab12-22222222"
  }
  accounts = {
    log-archive = { email = "me+log-archive@mydomain.test", ou = "Security" }
    dev         = { email = "me+dev@mydomain.test", ou = "NonProd" }
  }
}

run "accounts_land_in_their_ou_and_are_never_closed" {
  command = plan

  assert {
    condition     = aws_organizations_account.this["log-archive"].parent_id == "ou-ab12-11111111" && aws_organizations_account.this["dev"].parent_id == "ou-ab12-22222222"
    error_message = "Each account must be placed in the OU named in the registry."
  }

  assert {
    condition     = alltrue([for _, a in aws_organizations_account.this : a.close_on_deletion == false && a.iam_user_access_to_billing == "ALLOW"])
    error_message = "Accounts must never be closed on deletion and must allow IAM billing access."
  }
}

run "placeholder_email_is_rejected" {
  command = plan

  variables {
    accounts = {
      log-archive = { email = "aws+log-archive@example.com", ou = "Security" }
    }
  }

  expect_failures = [var.accounts]
}

run "duplicate_email_is_rejected" {
  command = plan

  variables {
    accounts = {
      acct-a = { email = "me+x@mydomain.test", ou = "Security" }
      acct-b = { email = "ME+X@mydomain.test", ou = "NonProd" }
    }
  }

  expect_failures = [var.accounts]
}

run "invalid_email_is_rejected" {
  command = plan

  variables {
    accounts = {
      acct-a = { email = "not-an-email", ou = "Security" }
    }
  }

  expect_failures = [var.accounts]
}

run "unknown_ou_is_rejected" {
  command = plan

  variables {
    accounts = {
      acct-a = { email = "me+a@mydomain.test", ou = "Nope" }
    }
  }

  expect_failures = [var.accounts]
}
