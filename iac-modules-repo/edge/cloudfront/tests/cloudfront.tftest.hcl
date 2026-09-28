# Tests for edge/cloudfront (PLAN 6.3)

# Offline unit tests (no AWS credentials): `terraform test` from this module directory.

mock_provider "aws" {}

run "defaults" {
  command = plan

  variables {
    name                               = "test-app"
    origin_bucket_name                 = "test-app-origin"
    origin_bucket_arn                  = "arn:aws:s3:::test-app-origin"
    origin_bucket_regional_domain_name = "test-app-origin.s3.eu-central-1.amazonaws.com"
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.this.signing_behavior == "always"
    error_message = "OAC signing behavior should be 'always'."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.enabled == true
    error_message = "Distribution should be enabled by default."
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 1
    error_message = "Response headers policy should be created by default."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Default viewer protocol policy should redirect to HTTPS."
  }
}

run "with_custom_domain" {
  command = plan

  variables {
    name                               = "custom-domain-app"
    origin_bucket_name                 = "custom-domain-origin"
    origin_bucket_arn                  = "arn:aws:s3:::custom-domain-origin"
    origin_bucket_regional_domain_name = "custom-domain-origin.s3.eu-central-1.amazonaws.com"
    aliases                            = ["app.example.com"]
    acm_certificate_arn                = "arn:aws:acm:us-east-1:111111111111:certificate/test-cert"
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.aliases) > 0
    error_message = "Distribution should have aliases when custom domain is configured."
  }
}

run "no_response_headers" {
  command = plan

  variables {
    name                               = "no-headers-app"
    origin_bucket_name                 = "no-headers-origin"
    origin_bucket_arn                  = "arn:aws:s3:::no-headers-origin"
    origin_bucket_regional_domain_name = "no-headers-origin.s3.eu-central-1.amazonaws.com"
    enable_response_headers_policy     = false
  }

  assert {
    condition     = length(aws_cloudfront_response_headers_policy.this) == 0
    error_message = "Response headers policy should not be created when disabled."
  }
}

run "bad_name" {
  command = plan

  variables {
    name                               = "X"
    origin_bucket_name                 = "test"
    origin_bucket_arn                  = "arn:aws:s3:::test"
    origin_bucket_regional_domain_name = "test.s3.eu-central-1.amazonaws.com"
  }

  expect_failures = [var.name]
}

run "bad_protocol_version" {
  command = plan

  variables {
    name                               = "test-app"
    origin_bucket_name                 = "test"
    origin_bucket_arn                  = "arn:aws:s3:::test"
    origin_bucket_regional_domain_name = "test.s3.eu-central-1.amazonaws.com"
    minimum_protocol_version           = "TLSv1"
  }

  expect_failures = [var.minimum_protocol_version]
}
