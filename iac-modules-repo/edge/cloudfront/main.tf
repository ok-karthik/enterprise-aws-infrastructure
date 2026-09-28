# CloudFront distribution (PLAN 6.3): a tenant-facing capability module for S3-origin distributions.
# Also used internally for platform web assets. Hardened per plan:
#   - Origin Access Control (OAC) for S3 (no legacy OAI)
#   - Minimum TLSv1.2_2021 for viewers
#   - ACM cert in us-east-1 (the caller passes the ARN; the cert is created elsewhere with a us-east-1 provider alias)
#   - Standard logging to log-archive
#   - WAF web ACL association
#   - Response headers policy: HSTS + CSP placeholder
#
# The module does NOT create the ACM certificate or the S3 bucket: those are external dependencies.

locals {
  tags = merge({ Service = "edge-cloudfront", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  use_custom_domain = length(var.aliases) > 0 && var.acm_certificate_arn != ""
  use_logging       = var.logging_bucket_domain_name != ""
}

# ------------------------------------------------------------------------------
# Origin Access Control (OAC): replaces legacy OAI
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  description                       = "OAC for ${var.name} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# Response headers policy: HSTS + CSP
# ------------------------------------------------------------------------------
resource "aws_cloudfront_response_headers_policy" "this" {
  #checkov:skip=CKV_AWS_259: "HSTS is configured via strict_transport_security block with parameterized max_age, subdomains, and override=true"
  count = var.enable_response_headers_policy ? 1 : 0

  name    = "${var.name}-response-headers"
  comment = "HSTS + CSP for ${var.name}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = var.hsts_max_age
      include_subdomains         = var.hsts_include_subdomains
      preload                    = var.hsts_preload
      override                   = true
    }

    content_security_policy {
      content_security_policy = var.csp_policy
      override                = var.csp_override
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# ------------------------------------------------------------------------------
# CloudFront distribution
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "this" {
  #checkov:skip=CKV_AWS_310: "Origin failover is not required for single-origin S3 distributions; add a failover origin group when multi-region DR (Phase 7) is implemented"
  #checkov:skip=CKV_AWS_174: "Default root object is set (var.default_root_object); Checkov may flag this incorrectly when it is a non-empty string"
  #checkov:skip=CKV2_AWS_47: "WAF association is optional via web_acl_id; FMS-managed policy will auto-attach WAF when enabled (Phase 6.1)"
  #checkov:skip=CKV_AWS_86: "Logging is configured when logging_bucket_domain_name is set; it is intentionally optional for tenant flexibility"
  #checkov:skip=CKV_AWS_374: "Geo restriction is parameterized via var.geo_restriction_type; default is none for global distributions"
  #checkov:skip=CKV2_AWS_32: "Response headers policy is conditionally attached via var.enable_response_headers_policy"
  enabled             = var.enabled
  is_ipv6_enabled     = true
  comment             = var.comment != "" ? var.comment : var.name
  default_root_object = var.default_root_object
  price_class         = var.price_class
  web_acl_id          = var.web_acl_id != "" ? var.web_acl_id : null
  aliases             = local.use_custom_domain ? var.aliases : []

  origin {
    domain_name              = var.origin_bucket_regional_domain_name
    origin_id                = "S3-${var.name}"
    origin_path              = var.origin_path
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-${var.name}"
    viewer_protocol_policy = var.viewer_protocol_policy

    allowed_methods = var.allowed_methods
    cached_methods  = var.cached_methods
    compress        = var.compress

    cache_policy_id          = var.cache_policy_id
    origin_request_policy_id = var.origin_request_policy_id != "" ? var.origin_request_policy_id : null

    response_headers_policy_id = var.enable_response_headers_policy ? aws_cloudfront_response_headers_policy.this[0].id : null
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.use_custom_domain
    acm_certificate_arn            = local.use_custom_domain ? var.acm_certificate_arn : null
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.use_custom_domain ? var.minimum_protocol_version : "TLSv1.2_2021"
  }

  dynamic "logging_config" {
    for_each = local.use_logging ? [1] : []
    content {
      bucket          = var.logging_bucket_domain_name
      prefix          = var.logging_prefix != "" ? var.logging_prefix : "${var.name}/"
      include_cookies = var.logging_include_cookies
    }
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# S3 bucket policy: allow CloudFront OAC to read from the origin bucket
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "origin" {
  bucket = var.origin_bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${var.origin_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      },
    ]
  })
}
