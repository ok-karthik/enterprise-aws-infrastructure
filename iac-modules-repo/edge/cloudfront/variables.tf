variable "name" {
  description = "Unique name for this CloudFront distribution (used in resource naming)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,60}$", var.name))
    error_message = "name must be 2-61 lowercase alphanumeric characters or hyphens."
  }
}

variable "comment" {
  description = "Comment for the CloudFront distribution (appears in the console)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# S3 origin
# ---------------------------------------------------------------------------

variable "origin_bucket_name" {
  description = "Name of the S3 bucket used as the CloudFront origin."
  type        = string
}

variable "origin_bucket_arn" {
  description = "ARN of the S3 bucket used as the CloudFront origin."
  type        = string

  validation {
    condition     = can(regex("^arn:", var.origin_bucket_arn))
    error_message = "origin_bucket_arn must be a valid ARN."
  }
}

variable "origin_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket (e.g. mybucket.s3.eu-central-1.amazonaws.com)."
  type        = string
}

variable "origin_path" {
  description = "Optional path prefix for requests to the origin (e.g. /public). Leave empty for root."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# TLS / Domain
# ---------------------------------------------------------------------------

variable "aliases" {
  description = "Alternate domain names (CNAMEs) for the distribution. Requires a matching ACM certificate."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate in us-east-1 for the custom domain. Required when aliases is not empty. The caller is responsible for creating this cert (typically with a provider alias for us-east-1)."
  type        = string
  default     = ""
}

variable "minimum_protocol_version" {
  description = "Minimum TLS version for viewer connections."
  type        = string
  default     = "TLSv1.2_2021"

  validation {
    condition     = contains(["TLSv1.2_2021", "TLSv1.2_2019", "TLSv1.2_2018"], var.minimum_protocol_version)
    error_message = "minimum_protocol_version must be TLSv1.2_2021 (recommended), TLSv1.2_2019, or TLSv1.2_2018."
  }
}

# ---------------------------------------------------------------------------
# WAF
# ---------------------------------------------------------------------------

variable "web_acl_id" {
  description = "ARN of the WAFv2 web ACL to associate with the distribution. Empty = no WAF association (the FMS-managed policy will attach one automatically if FMS covers CloudFront)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

variable "logging_bucket_domain_name" {
  description = "Domain name of the S3 bucket for CloudFront standard access logs (e.g. platform-cloudfront-access-111111111111-eu-central-1.s3.amazonaws.com). Empty = no logging."
  type        = string
  default     = ""
}

variable "logging_prefix" {
  description = "Prefix for log objects in the logging bucket."
  type        = string
  default     = ""
}

variable "logging_include_cookies" {
  description = "Include cookies in access logs."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Cache behaviour
# ---------------------------------------------------------------------------

variable "default_root_object" {
  description = "Object returned for requests to the root URL (e.g. index.html)."
  type        = string
  default     = "index.html"
}

variable "allowed_methods" {
  description = "HTTP methods allowed (GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE)."
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cached_methods" {
  description = "HTTP methods whose responses are cached."
  type        = list(string)
  default     = ["GET", "HEAD"]
}

variable "compress" {
  description = "Compress objects automatically."
  type        = bool
  default     = true
}

variable "viewer_protocol_policy" {
  description = "Protocol policy for viewers: redirect-to-https, allow-all, or https-only."
  type        = string
  default     = "redirect-to-https"

  validation {
    condition     = contains(["redirect-to-https", "allow-all", "https-only"], var.viewer_protocol_policy)
    error_message = "viewer_protocol_policy must be redirect-to-https, allow-all, or https-only."
  }
}

variable "cache_policy_id" {
  description = "ID of a managed or custom cache policy. Defaults to CachingOptimized."
  type        = string
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
}

variable "origin_request_policy_id" {
  description = "ID of an origin request policy. Empty = none."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Response headers policy (HSTS, CSP)
# ---------------------------------------------------------------------------

variable "enable_response_headers_policy" {
  description = "Create and attach a response headers policy with HSTS and CSP."
  type        = bool
  default     = true
}

variable "hsts_max_age" {
  description = "HSTS max-age in seconds (default 1 year)."
  type        = number
  default     = 31536000

  validation {
    condition     = var.hsts_max_age >= 0
    error_message = "hsts_max_age must be >= 0."
  }
}

variable "hsts_include_subdomains" {
  description = "Include subdomains in the HSTS header."
  type        = bool
  default     = true
}

variable "hsts_preload" {
  description = "Enable HSTS preload. Only set this after verifying the domain is eligible."
  type        = bool
  default     = false
}

variable "csp_policy" {
  description = "Content-Security-Policy header value. Set to a real CSP before going to production."
  type        = string
  default     = "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self' 'unsafe-inline'"
}

variable "csp_override" {
  description = "Whether the CSP header overrides the origin's CSP."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Geo restriction
# ---------------------------------------------------------------------------

variable "geo_restriction_type" {
  description = "Geo restriction type: none, whitelist, or blacklist."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "geo_restriction_type must be none, whitelist, or blacklist."
  }
}

variable "geo_restriction_locations" {
  description = "ISO 3166-1 alpha-2 country codes for geo restriction."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------

variable "enabled" {
  description = "Whether the distribution is enabled."
  type        = bool
  default     = true
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
