# data/postgres

Tenant-facing capability module for provisioning dedicated PostgreSQL databases. Consumed by `internal-developer-platform` catalog templates.

Enforces non-negotiable security guardrails:
- Encryption-at-rest via AWS KMS
- Credentials managed and rotated automatically by AWS Secrets Manager (no plaintext in state)
- Non-publicly accessible by default, placed inside VPC database subnets with strict security groups
- Automated daily backups

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [random_string.db_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Application the database belongs to | `string` | n/a | yes |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | Automated backup retention period in days | `number` | `7` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Major PostgreSQL engine version | `string` | `"16"` | no |
| <a name="input_env"></a> [env](#input\_env) | Target environment (dev, staging, prod) | `string` | `"dev"` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | RDS instance class size | `string` | `"db.t3.micro"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the DB subnet group. Empty means none is created. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource, supplied by the scaffolder | `map(string)` | `{}` | no |
| <a name="input_team_name"></a> [team\_name](#input\_team\_name) | Team or tenant that owns this database | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to place the database security group in. Empty means no security group is created. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_endpoint"></a> [db\_endpoint](#output\_db\_endpoint) | Connection endpoint for the RDS instance |
| <a name="output_db_identifier"></a> [db\_identifier](#output\_db\_identifier) | Generated RDS identifier, including the uniqueness suffix |
| <a name="output_master_secret_arn"></a> [master\_secret\_arn](#output\_master\_secret\_arn) | Secrets Manager ARN holding the master user password |
<!-- END_TF_DOCS -->
