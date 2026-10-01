# security/waf-logging

**Status:** 📐 Design-only (tested offline; not wired into a live stack)

WAF logging pipeline (PLAN 6.2): Kinesis Data Firehose delivery stream that ships
WAFv2 logs to the central **log-archive** S3 bucket with GZIP compression and
redaction of sensitive HTTP request fields.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.firehose` | IAM role for Firehose (S3 write + KMS encrypt) |
| `aws_kinesis_firehose_delivery_stream.waf_logs` | Delivery stream named `aws-waf-logs-<prefix>` |
| `aws_wafv2_web_acl_logging_configuration` | Attaches logging + field redaction to each web ACL |

### Default redaction

The `authorization` and `cookie` HTTP headers are redacted from WAF logs by
default. Override the `redacted_fields` variable to change this.

## Prerequisites

1. The WAF log bucket exists in log-archive (`security/log-archive` with `"waf"` in
   `enabled_log_types`). It is named `aws-waf-logs-<name_prefix>-<account>-<region>`.
2. The KMS key in log-archive allows `firehose.amazonaws.com` to
   `kms:GenerateDataKey` and `kms:Decrypt` (already granted by log-archive's key policy
   via the `delivery.logs.amazonaws.com` service principal statement).

## Usage

```hcl
module "waf_logging" {
  source = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/waf-logging?ref=waf-logging-v1.0.0"

  log_archive_bucket_arn  = "arn:aws:s3:::aws-waf-logs-platform-111111111111-eu-central-1"
  log_archive_bucket_name = "aws-waf-logs-platform-111111111111-eu-central-1"
  log_archive_kms_key_arn = "arn:aws:kms:eu-central-1:111111111111:key/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  web_acl_arns = [
    "arn:aws:wafv2:eu-central-1:222222222222:regional/webacl/platform-waf/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `name_prefix` | Prefix for resources (Firehose = `aws-waf-logs-<prefix>`) | `string` | `"platform"` | no |
| `log_archive_bucket_arn` | ARN of the WAF log bucket | `string` | — | yes |
| `log_archive_bucket_name` | Name of the WAF log bucket | `string` | — | yes |
| `log_archive_kms_key_arn` | ARN of the KMS key for the WAF log bucket | `string` | — | yes |
| `web_acl_arns` | Web ACL ARNs to attach logging to | `list(string)` | `[]` | no |
| `redacted_fields` | HTTP fields to redact | `list(object)` | authorization, cookie | no |
| `buffering_interval` | Firehose buffering interval (seconds) | `number` | `300` | no |
| `buffering_size` | Firehose buffering size (MiB) | `number` | `5` | no |
| `tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `firehose_arn` | ARN of the Firehose delivery stream |
| `firehose_name` | Name of the Firehose delivery stream |
| `firehose_role_arn` | ARN of the Firehose IAM role |

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
| [aws_iam_role.firehose](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.firehose_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kinesis_firehose_delivery_stream.waf_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_firehose_delivery_stream) | resource |
| [aws_wafv2_web_acl_logging_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_buffering_interval"></a> [buffering\_interval](#input\_buffering\_interval) | Firehose buffering interval in seconds (60-900). | `number` | `300` | no |
| <a name="input_buffering_size"></a> [buffering\_size](#input\_buffering\_size) | Firehose buffering size in MiB (1-128). | `number` | `5` | no |
| <a name="input_log_archive_bucket_arn"></a> [log\_archive\_bucket\_arn](#input\_log\_archive\_bucket\_arn) | ARN of the log-archive S3 bucket for WAF logs (security/log-archive's bucket\_arns["waf"] output). | `string` | n/a | yes |
| <a name="input_log_archive_kms_key_arn"></a> [log\_archive\_kms\_key\_arn](#input\_log\_archive\_kms\_key\_arn) | ARN of the KMS key used by the WAF log bucket in log-archive. Firehose needs kms:GenerateDataKey and kms:Decrypt. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for all resource names. The Firehose delivery stream is named aws-waf-logs-<name\_prefix> (the 'aws-waf-logs-' prefix is required by WAFv2). | `string` | `"platform"` | no |
| <a name="input_redacted_fields"></a> [redacted\_fields](#input\_redacted\_fields) | HTTP request fields to redact from WAF logs. Each entry is a map with one key:<br/>"single\_header" (header name, lowercased), "method", "query\_string", or "uri\_path".<br/>Default redacts the authorization and cookie headers. | <pre>list(object({<br/>    single_header = optional(object({ name = string }))<br/>    method        = optional(object({}))<br/>    query_string  = optional(object({}))<br/>    uri_path      = optional(object({}))<br/>  }))</pre> | <pre>[<br/>  {<br/>    "method": null,<br/>    "query_string": null,<br/>    "single_header": {<br/>      "name": "authorization"<br/>    },<br/>    "uri_path": null<br/>  },<br/>  {<br/>    "method": null,<br/>    "query_string": null,<br/>    "single_header": {<br/>      "name": "cookie"<br/>    },<br/>    "uri_path": null<br/>  }<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_web_acl_arns"></a> [web\_acl\_arns](#input\_web\_acl\_arns) | ARNs of the WAFv2 web ACLs to attach logging to. Can be regional or CloudFront (global) web ACLs. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_firehose_arn"></a> [firehose\_arn](#output\_firehose\_arn) | ARN of the Kinesis Data Firehose delivery stream for WAF logs |
| <a name="output_firehose_name"></a> [firehose\_name](#output\_firehose\_name) | Name of the Firehose delivery stream (starts with aws-waf-logs-) |
| <a name="output_firehose_role_arn"></a> [firehose\_role\_arn](#output\_firehose\_role\_arn) | ARN of the IAM role used by Firehose |
<!-- END_TF_DOCS -->
