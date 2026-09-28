# network/route53-failover

DNS failover between two regions (PLAN 7.4): one health check on the primary endpoint and a PRIMARY / SECONDARY
pair of alias records. While the health check passes, clients get the primary. When it fails, Route 53 answers
with the secondary. The secondary has no health check on purpose: it is the last resort and must always answer.

## Things to know

- **Cutover time** = `request_interval x failure_threshold` (90 s by default) plus resolver caching. Alias records
  have no TTL of their own. Lower it with `request_interval = 10` (costs more per health check).
- Point `health_check.fqdn` at the **primary endpoint itself** (the ALB name), not at the failover name, or the
  check follows the failover and flaps.
- This is **automatic** failover of the *front door* only. Databases are not promoted by DNS. For Aurora Global
  Database, promotion is a separate, human-run step (see `DISASTER_RECOVERY.md`).
- **Route 53 Application Recovery Controller (ARC)** for prod: health-check-driven failover can flip on a false
  alarm and cannot be blocked. ARC routing controls put the switch in a human's hands (or an automation with
  safety rules such as "never turn both regions off"), across 5 regional cluster endpoints. It costs roughly
  $2.5 per hour per cluster (about $1,800 a month), which is why this module does not include it. Decide it in
  the prod ADR, and see `FINOPS.md`.
- Route 53 health check metrics live in **us-east-1**, so a CloudWatch alarm on `health_check_id` must be created
  there.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_health_check.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_health_check) | resource |
| [aws_route53_record.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_evaluate_target_health"></a> [evaluate\_target\_health](#input\_evaluate\_target\_health) | Also treat an unhealthy alias target (for example an ALB with no healthy targets) as a failure | `bool` | `true` | no |
| <a name="input_health_check"></a> [health\_check](#input\_health\_check) | Health check that decides when traffic leaves the primary. Point fqdn at the primary endpoint itself, not at the failover name. | <pre>object({<br/>    fqdn              = string<br/>    port              = optional(number, 443)<br/>    type              = optional(string, "HTTPS")<br/>    path              = optional(string, "/healthz")<br/>    failure_threshold = optional(number, 3)<br/>    request_interval  = optional(number, 30)<br/>  })</pre> | n/a | yes |
| <a name="input_primary"></a> [primary](#input\_primary) | Primary endpoint as an alias target (for example the ALB's dns\_name and zone\_id in eu-central-1) | <pre>object({<br/>    dns_name = string<br/>    zone_id  = string<br/>  })</pre> | n/a | yes |
| <a name="input_record_name"></a> [record\_name](#input\_record\_name) | Fully qualified name clients use, for example api.example.com | `string` | n/a | yes |
| <a name="input_secondary"></a> [secondary](#input\_secondary) | Secondary (DR) endpoint as an alias target (the ALB in eu-west-1) | <pre>object({<br/>    dns_name = string<br/>    zone_id  = string<br/>  })</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for the health check | `map(string)` | `{}` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Route 53 hosted zone that holds the record (from network/dns) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_health_check_id"></a> [health\_check\_id](#output\_health\_check\_id) | ID of the primary's health check (alarm on it in CloudWatch, us-east-1) |
| <a name="output_record_fqdn"></a> [record\_fqdn](#output\_record\_fqdn) | Failover record name |
<!-- END_TF_DOCS -->
