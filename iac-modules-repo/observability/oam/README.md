# observability/oam

**Status:** 📝 Plan-only (wired into `foundation-live-repo`; not applied to AWS)

CloudWatch **cross-account observability** (PLAN 9.1): one place (the observability account) to see the metrics
and logs of every account, without copying data or logging in to each account.

| `mode` | Applied in | Creates |
|---|---|---|
| `sink` | the observability account | an OAM sink, a sink policy that lets only your organization link to it, and optionally a Managed Prometheus workspace |
| `link` | a source account | an OAM link to the sink |

Workload accounts normally get their link from `governance/account-baseline` (set `observability_sink_arn`), so this
module's `link` mode is for accounts that do not use the baseline.

## Things to know

- **Regional.** A link only reaches a sink in the **same region**. Apply the sink in each region you observe
  (start with `eu-central-1`) and give each source account the matching sink ARN.
- **Order:** sink first (its `sink_arn` output), then the links.
- **Data stays in the source account.** The monitoring account reads it through the link. Deleting the link stops access.
- Logs and metrics can contain personal data. The sink policy limits who can *link*; who can *read* in the
  observability account is an IAM Identity Center decision (least privilege, see `docs/IDENTITY.md`).
- **Managed Grafana is not created here.** It needs IAM Identity Center or SAML wiring and is a separate decision.
  `enable_prometheus` only creates the workspace, and it costs per ingested sample: see `FINOPS.md`.
- Not applied anywhere yet: the observability account has a placeholder id in `_config/accounts.hcl`.

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
| [aws_oam_link.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/oam_link) | resource |
| [aws_oam_sink.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/oam_sink) | resource |
| [aws_oam_sink_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/oam_sink_policy) | resource |
| [aws_prometheus_workspace.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/prometheus_workspace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_enable_prometheus"></a> [enable\_prometheus](#input\_enable\_prometheus) | sink mode, optional: create an Amazon Managed Service for Prometheus workspace in the observability account. Costs per ingested sample. Managed Grafana is not created here: it needs IAM Identity Center wiring and is a separate decision. | `bool` | `false` | no |
| <a name="input_label_template"></a> [label\_template](#input\_label\_template) | link mode: how this account is labelled in the monitoring account's console. $AccountName is the account's name. | `string` | `"$AccountName"` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | sink = the monitoring (observability) account's side: receives data from the organization. link = a source account's side: sends its metrics, logs and traces to the sink. | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | sink mode: ID of the AWS Organization (o-xxxxxxxxxx). The sink policy lets only accounts of this organization link to it. | `string` | `""` | no |
| <a name="input_prometheus_alias"></a> [prometheus\_alias](#input\_prometheus\_alias) | Alias of the Prometheus workspace when enable\_prometheus is true. | `string` | `"platform"` | no |
| <a name="input_resource_types"></a> [resource\_types](#input\_resource\_types) | What is shared. Metrics and logs by default; add AWS::XRay::Trace for traces. | `list(string)` | <pre>[<br/>  "AWS::CloudWatch::Metric",<br/>  "AWS::Logs::LogGroup"<br/>]</pre> | no |
| <a name="input_sink_arn"></a> [sink\_arn](#input\_sink\_arn) | link mode: ARN of the sink in the observability account (same region as this account's link). Also readable from the sink stack's sink\_arn output. | `string` | `""` | no |
| <a name="input_sink_name"></a> [sink\_name](#input\_sink\_name) | sink mode: name of the sink (letters, digits, hyphens; unique per account and region). | `string` | `"platform-observability"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_link_arn"></a> [link\_arn](#output\_link\_arn) | link mode: ARN of this account's link. Empty in sink mode. |
| <a name="output_prometheus_workspace_arn"></a> [prometheus\_workspace\_arn](#output\_prometheus\_workspace\_arn) | ARN of the Managed Prometheus workspace. Empty unless enable\_prometheus is true. |
| <a name="output_sink_arn"></a> [sink\_arn](#output\_sink\_arn) | sink mode: ARN of the sink. Give it to every source account's link (sink\_arn). Empty in link mode. |
<!-- END_TF_DOCS -->
