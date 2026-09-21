# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }
}

variables {
  hub_ack_controller_role_arn = "arn:aws:iam::444455556666:role/ack-controller"
  hub_account_id              = "444455556666"
}

run "ack_spoke_has_no_admin_managed_policies" {
  command = apply

  assert {
    condition     = length(aws_iam_role.ack_spoke[0].managed_policy_arns) == 0 || length(setintersection(aws_iam_role.ack_spoke[0].managed_policy_arns, ["arn:aws:iam::aws:policy/IAMFullAccess", "arn:aws:iam::aws:policy/AmazonS3FullAccess"])) == 0
    error_message = "The ACK spoke role must not carry IAMFullAccess or AmazonS3FullAccess."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.ack_spoke_scoped[0].policy, "\"iam:*\"") && !strcontains(aws_iam_role_policy.ack_spoke_scoped[0].policy, "\"s3:*\"")
    error_message = "The scoped ACK policy must not contain service-wide wildcards."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.ack_spoke_scoped[0].policy, "arn:aws:s3:::platform-ack-*") && strcontains(aws_iam_role_policy.ack_spoke_scoped[0].policy, "arn:aws:iam::111122223333:role/ack/*")
    error_message = "S3 and IAM must be scoped to the bucket prefix and the role path in this account."
  }
}

run "ack_role_creation_requires_boundary" {
  command = apply

  assert {
    condition     = strcontains(aws_iam_role_policy.ack_spoke_scoped[0].policy, "iam:PermissionsBoundary")
    error_message = "iam:CreateRole must be conditioned on the ack-tenant-boundary."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.ack_spoke_scoped[0].policy, "DeleteRolePermissionsBoundary")
    error_message = "The spoke role must not be able to strip the boundary from a role."
  }
}

run "empty_bucket_prefix_is_rejected" {
  command = plan

  variables {
    ack_s3_bucket_prefix = ""
  }

  expect_failures = [var.ack_s3_bucket_prefix]
}
