# identity/workload-iam

Tenant-facing capability module interface for workload identity. Consumed by `internal-developer-platform` catalog templates.

Currently a documented stub: produces valid Terraform that plans cleanly while the cross-capability dependency wiring (OIDC issuer / Pod Identity association) is resolved.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Application the identity belongs to | `string` | n/a | yes |
| <a name="input_env"></a> [env](#input\_env) | Target environment (dev, staging, prod) | `string` | `"dev"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource, supplied by the scaffolder | `map(string)` | `{}` | no |
| <a name="input_team_name"></a> [team\_name](#input\_team\_name) | Team or tenant that owns this identity | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_planned_role_name"></a> [planned\_role\_name](#output\_planned\_role\_name) | Role name this capability will create once implemented |
<!-- END_TF_DOCS -->
