# governance/discovery-publisher

Writes the platform **discovery contract** into one account, with the same parameter names in every workload account (`/platform/<env>/<region>/...`), so tenant Terraform reads its own account whatever account the underlying resource lives in (for example a VPC shared from a network hub). Only keys of the contract are accepted; see [`docs/DISCOVERY_CONTRACT.md`](../../../docs/DISCOVERY_CONTRACT.md).

The values come from the outputs of the stacks that own them (VPC, EKS, ...), passed in by the live leaf. This module is the **single owner** of those names: the VPC and EKS blueprints set `publish_ssm_parameters = false`, or two resources would fight over one name. The `account/*`, `kms/*` and `iam/*` keys are published by `governance/account-baseline`.

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
| [aws_ssm_parameter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_env"></a> [env](#input\_env) | Environment of this account (dev, staging, prod, global). Part of every parameter name. | `string` | n/a | yes |
| <a name="input_parameters"></a> [parameters](#input\_parameters) | Discovery parameters to publish, keyed by contract key (the part after /platform/<env>/<region>/), value<br/>is the string to store. Only keys of the discovery contract are accepted, so tenant modules can rely on<br/>the names (see docs/DISCOVERY\_CONTRACT.md). Values normally come from the outputs of the stacks that own them. | `map(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Region the parameters are published for (part of every parameter name). | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_parameter_names"></a> [parameter\_names](#output\_parameter\_names) | Full names of the published parameters, keyed by contract key |
<!-- END_TF_DOCS -->
