# edge/cloudfront

**Status:** 📐 Design-only (tested offline; not wired into a live stack)

Hardened CloudFront distribution module (PLAN 6.3): a **tenant-facing capability**
and an internal platform module. Backed by an S3 origin with Origin Access Control
(OAC), minimum TLSv1.2_2021, standard logging, WAF association and a response
headers policy (HSTS + Content Security Policy).

## What it creates

| Resource | Purpose |
|---|---|
| `aws_cloudfront_origin_access_control` | OAC for S3 origin (replaces legacy OAI) |
| `aws_cloudfront_response_headers_policy` | HSTS + CSP + X-Content-Type-Options + X-Frame-Options + Referrer-Policy |
| `aws_cloudfront_distribution` | The distribution itself |
| `aws_s3_bucket_policy` | Grants CloudFront OAC read access to the origin bucket |

## Security hardening

- **OAC**, not legacy OAI: every request to S3 is signed with SigV4.
- **TLSv1.2_2021** minimum (the strictest CloudFront viewer certificate policy).
- **HSTS** with a 1-year max-age, includeSubDomains, optional preload.
- **CSP** placeholder — set a real policy before going to production.
- **X-Frame-Options: DENY**, **X-Content-Type-Options: nosniff**,
  **Referrer-Policy: strict-origin-when-cross-origin**.
- WAF web ACL association (explicit via `web_acl_id`, or automatic via FMS Phase 6.1).

## ACM certificate

CloudFront requires the ACM certificate to be in **us-east-1**. The caller creates
it (typically with a provider alias) and passes the ARN:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_acm_certificate" "cdn" {
  provider          = aws.us_east_1
  domain_name       = "app.example.com"
  validation_method = "DNS"
}

module "cloudfront" {
  source = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/edge/cloudfront?ref=cloudfront-v1.0.0"

  name                               = "my-app"
  origin_bucket_name                 = "my-app-assets"
  origin_bucket_arn                  = "arn:aws:s3:::my-app-assets"
  origin_bucket_regional_domain_name = "my-app-assets.s3.eu-central-1.amazonaws.com"

  aliases             = ["app.example.com"]
  acm_certificate_arn = aws_acm_certificate.cdn.arn
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name` | Distribution name | `string` | — | yes |
| `origin_bucket_name` | S3 origin bucket name | `string` | — | yes |
| `origin_bucket_arn` | S3 origin bucket ARN | `string` | — | yes |
| `origin_bucket_regional_domain_name` | S3 regional domain | `string` | — | yes |
| `origin_path` | Origin path prefix | `string` | `""` | no |
| `aliases` | Custom domain names | `list(string)` | `[]` | no |
| `acm_certificate_arn` | ACM cert ARN (us-east-1) | `string` | `""` | no |
| `minimum_protocol_version` | Viewer TLS version | `string` | `"TLSv1.2_2021"` | no |
| `web_acl_id` | WAFv2 web ACL ARN | `string` | `""` | no |
| `logging_bucket_domain_name` | Log bucket domain | `string` | `""` | no |
| `logging_prefix` | Log object prefix | `string` | `""` | no |
| `default_root_object` | Root URL object | `string` | `"index.html"` | no |
| `viewer_protocol_policy` | Viewer protocol | `string` | `"redirect-to-https"` | no |
| `cache_policy_id` | Cache policy ID | `string` | CachingOptimized | no |
| `enable_response_headers_policy` | Create HSTS+CSP policy | `bool` | `true` | no |
| `hsts_max_age` | HSTS max-age (seconds) | `number` | `31536000` | no |
| `csp_policy` | CSP header value | `string` | `"default-src 'self'…"` | no |
| `geo_restriction_type` | none/whitelist/blacklist | `string` | `"none"` | no |
| `price_class` | Price class | `string` | `"PriceClass_100"` | no |
| `tags` | Tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `distribution_id` | CloudFront distribution ID |
| `distribution_arn` | CloudFront distribution ARN |
| `distribution_domain_name` | CloudFront domain name |
| `distribution_hosted_zone_id` | Route 53 hosted zone ID |
| `oac_id` | Origin Access Control ID |
| `response_headers_policy_id` | Response headers policy ID |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_cloudfront_response_headers_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_response_headers_policy) | resource |
| [aws_s3_bucket_policy.origin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_acm_certificate_arn"></a> [acm\_certificate\_arn](#input\_acm\_certificate\_arn) | ARN of the ACM certificate in us-east-1 for the custom domain. Required when aliases is not empty. The caller is responsible for creating this cert (typically with a provider alias for us-east-1). | `string` | `""` | no |
| <a name="input_aliases"></a> [aliases](#input\_aliases) | Alternate domain names (CNAMEs) for the distribution. Requires a matching ACM certificate. | `list(string)` | `[]` | no |
| <a name="input_allowed_methods"></a> [allowed\_methods](#input\_allowed\_methods) | HTTP methods allowed (GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE). | `list(string)` | <pre>[<br/>  "GET",<br/>  "HEAD",<br/>  "OPTIONS"<br/>]</pre> | no |
| <a name="input_cache_policy_id"></a> [cache\_policy\_id](#input\_cache\_policy\_id) | ID of a managed or custom cache policy. Defaults to CachingOptimized. | `string` | `"658327ea-f89d-4fab-a63d-7e88639e58f6"` | no |
| <a name="input_cached_methods"></a> [cached\_methods](#input\_cached\_methods) | HTTP methods whose responses are cached. | `list(string)` | <pre>[<br/>  "GET",<br/>  "HEAD"<br/>]</pre> | no |
| <a name="input_comment"></a> [comment](#input\_comment) | Comment for the CloudFront distribution (appears in the console). | `string` | `""` | no |
| <a name="input_compress"></a> [compress](#input\_compress) | Compress objects automatically. | `bool` | `true` | no |
| <a name="input_csp_override"></a> [csp\_override](#input\_csp\_override) | Whether the CSP header overrides the origin's CSP. | `bool` | `true` | no |
| <a name="input_csp_policy"></a> [csp\_policy](#input\_csp\_policy) | Content-Security-Policy header value. Set to a real CSP before going to production. | `string` | `"default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self' 'unsafe-inline'"` | no |
| <a name="input_default_root_object"></a> [default\_root\_object](#input\_default\_root\_object) | Object returned for requests to the root URL (e.g. index.html). | `string` | `"index.html"` | no |
| <a name="input_enable_response_headers_policy"></a> [enable\_response\_headers\_policy](#input\_enable\_response\_headers\_policy) | Create and attach a response headers policy with HSTS and CSP. | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether the distribution is enabled. | `bool` | `true` | no |
| <a name="input_geo_restriction_locations"></a> [geo\_restriction\_locations](#input\_geo\_restriction\_locations) | ISO 3166-1 alpha-2 country codes for geo restriction. | `list(string)` | `[]` | no |
| <a name="input_geo_restriction_type"></a> [geo\_restriction\_type](#input\_geo\_restriction\_type) | Geo restriction type: none, whitelist, or blacklist. | `string` | `"none"` | no |
| <a name="input_hsts_include_subdomains"></a> [hsts\_include\_subdomains](#input\_hsts\_include\_subdomains) | Include subdomains in the HSTS header. | `bool` | `true` | no |
| <a name="input_hsts_max_age"></a> [hsts\_max\_age](#input\_hsts\_max\_age) | HSTS max-age in seconds (default 1 year). | `number` | `31536000` | no |
| <a name="input_hsts_preload"></a> [hsts\_preload](#input\_hsts\_preload) | Enable HSTS preload. Only set this after verifying the domain is eligible. | `bool` | `false` | no |
| <a name="input_logging_bucket_domain_name"></a> [logging\_bucket\_domain\_name](#input\_logging\_bucket\_domain\_name) | Domain name of the S3 bucket for CloudFront standard access logs (e.g. platform-cloudfront-access-111111111111-eu-central-1.s3.amazonaws.com). Empty = no logging. | `string` | `""` | no |
| <a name="input_logging_include_cookies"></a> [logging\_include\_cookies](#input\_logging\_include\_cookies) | Include cookies in access logs. | `bool` | `false` | no |
| <a name="input_logging_prefix"></a> [logging\_prefix](#input\_logging\_prefix) | Prefix for log objects in the logging bucket. | `string` | `""` | no |
| <a name="input_minimum_protocol_version"></a> [minimum\_protocol\_version](#input\_minimum\_protocol\_version) | Minimum TLS version for viewer connections. | `string` | `"TLSv1.2_2021"` | no |
| <a name="input_name"></a> [name](#input\_name) | Unique name for this CloudFront distribution (used in resource naming). | `string` | n/a | yes |
| <a name="input_origin_bucket_arn"></a> [origin\_bucket\_arn](#input\_origin\_bucket\_arn) | ARN of the S3 bucket used as the CloudFront origin. | `string` | n/a | yes |
| <a name="input_origin_bucket_name"></a> [origin\_bucket\_name](#input\_origin\_bucket\_name) | Name of the S3 bucket used as the CloudFront origin. | `string` | n/a | yes |
| <a name="input_origin_bucket_regional_domain_name"></a> [origin\_bucket\_regional\_domain\_name](#input\_origin\_bucket\_regional\_domain\_name) | Regional domain name of the S3 bucket (e.g. mybucket.s3.eu-central-1.amazonaws.com). | `string` | n/a | yes |
| <a name="input_origin_path"></a> [origin\_path](#input\_origin\_path) | Optional path prefix for requests to the origin (e.g. /public). Leave empty for root. | `string` | `""` | no |
| <a name="input_origin_request_policy_id"></a> [origin\_request\_policy\_id](#input\_origin\_request\_policy\_id) | ID of an origin request policy. Empty = none. | `string` | `""` | no |
| <a name="input_price_class"></a> [price\_class](#input\_price\_class) | CloudFront price class. | `string` | `"PriceClass_100"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_viewer_protocol_policy"></a> [viewer\_protocol\_policy](#input\_viewer\_protocol\_policy) | Protocol policy for viewers: redirect-to-https, allow-all, or https-only. | `string` | `"redirect-to-https"` | no |
| <a name="input_web_acl_id"></a> [web\_acl\_id](#input\_web\_acl\_id) | ARN of the WAFv2 web ACL to associate with the distribution. Empty = no WAF association (the FMS-managed policy will attach one automatically if FMS covers CloudFront). | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_distribution_arn"></a> [distribution\_arn](#output\_distribution\_arn) | ARN of the CloudFront distribution |
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | Domain name of the CloudFront distribution (e.g. d111111abcdef8.cloudfront.net) |
| <a name="output_distribution_hosted_zone_id"></a> [distribution\_hosted\_zone\_id](#output\_distribution\_hosted\_zone\_id) | Route 53 hosted zone ID for the CloudFront distribution (for alias records) |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the CloudFront distribution |
| <a name="output_oac_id"></a> [oac\_id](#output\_oac\_id) | ID of the Origin Access Control |
| <a name="output_response_headers_policy_id"></a> [response\_headers\_policy\_id](#output\_response\_headers\_policy\_id) | ID of the response headers policy (empty when disabled) |
<!-- END_TF_DOCS -->
