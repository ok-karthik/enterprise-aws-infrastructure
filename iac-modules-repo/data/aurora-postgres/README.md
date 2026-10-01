# data/aurora-postgres

**Status:** 📐 Design-only (tested offline; not wired into a live stack)

Aurora PostgreSQL for production data (PLAN 7.3), with an optional **Aurora Global Database** for a second
region. `data/postgres` stays the cheap single-instance RDS for NonProd; use this module when a database must
survive the loss of a region.

## Modes

| `mode` | What it makes | Where you apply it |
|---|---|---|
| `standalone` | One Aurora cluster. Password managed by Secrets Manager (rotated by RDS). | any region |
| `global_primary` | The global cluster **and** the writer cluster. | primary region (`eu-central-1`) |
| `global_secondary` | A read-only cluster that joins the global cluster. | secondary region (`eu-west-1`) |

Apply order for a global database: primary first, then feed its `global_cluster_identifier` output into the
secondary's `global_cluster_identifier` input, with `source_region` set to the primary's region and a
`kms_key_id` from the **secondary** region (encrypted storage cannot use the primary region's key).

## Things that are not obvious

- **The password.** AWS does not support Secrets Manager-managed passwords for clusters in a global database.
  In `global_primary` mode the module generates the password as an *ephemeral* value and passes it to RDS and to a
  Secrets Manager secret through write-only arguments, so it is never written to state. That needs
  Terraform 1.11+ and AWS provider 6.x. The secret is **not rotated automatically**: rotate it by bumping the
  write-only version in a follow-up change, or add a rotation Lambda per region.
- **Failover is not automatic.** If the primary region is lost, someone must *promote* the secondary
  (`aws rds failover-global-cluster` for a planned switch, or `remove-from-global-cluster` for an unplanned one)
  and then update Terraform. The steps are in `DISASTER_RECOVERY.md`. Typical RPO is about 1 second and RTO
  about 1 minute for the database itself, plus your own DNS and app cutover time.
- **No burstable classes.** Global Database needs `db.r*` or `db.x*`. The default is `db.r6g.large`, which is
  the reason this costs far more than `data/postgres` (see `FINOPS.md`).
- `engine_version`, `global_cluster_identifier` and `replication_source_identifier` are in `ignore_changes`
  because AWS changes them itself during a failover or a global upgrade.

## Usage

```hcl
# eu-central-1
module "aurora" {
  source     = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/data/aurora-postgres?ref=aurora-postgres-v1.0.0"
  mode       = "global_primary"
  team_name  = "payments"
  app_name   = "ledger"
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.database_subnets
  kms_key_id = dependency.kms.outputs.key_arn
}

# eu-west-1 (a separate stack, applied after the one above)
module "aurora_dr" {
  source                    = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/data/aurora-postgres?ref=aurora-postgres-v1.0.0"
  mode                      = "global_secondary"
  global_cluster_identifier = "<global_cluster_identifier output of the primary>"
  source_region             = "eu-central-1"
  kms_key_id                = "<KMS key in eu-west-1>"
  # team_name, app_name, vpc_id, subnet_ids as above, for the eu-west-1 VPC
}
```

Tests: `terraform test` (offline, mock AWS provider; the real `random` provider is used because mock providers
cannot replace ephemeral resources).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.7 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_global_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster) | resource |
| [aws_secretsmanager_secret.master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cidrs"></a> [allowed\_cidrs](#input\_allowed\_cidrs) | CIDRs allowed to reach PostgreSQL (5432). Default is the private supernet, never the internet. | `list(string)` | <pre>[<br/>  "10.0.0.0/8"<br/>]</pre> | no |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Application the database belongs to | `string` | n/a | yes |
| <a name="input_backup_retention_days"></a> [backup\_retention\_days](#input\_backup\_retention\_days) | Automated backup retention in days. | `number` | `14` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Block deletion of the cluster (and global cluster) until turned off in a separate change. | `bool` | `true` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Aurora PostgreSQL engine version. Must match between the global cluster, the primary and every secondary. | `string` | `"16.6"` | no |
| <a name="input_env"></a> [env](#input\_env) | Target environment (dev, staging, prod) | `string` | `"prod"` | no |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global\_cluster\_identifier) | global\_secondary only: the global cluster to join (the global\_cluster\_identifier output of the primary). | `string` | `""` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class. Aurora Global Database does not support the burstable db.t* classes. | `string` | `"db.r6g.large"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of instances in this cluster (1 writer + readers). 2 or more spreads across AZs. | `number` | `2` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | Customer-managed KMS key ARN in THIS region for the cluster storage. Required for global\_secondary (a key in the secondary region), recommended for the primary. | `string` | `""` | no |
| <a name="input_mode"></a> [mode](#input\_mode) | standalone       a normal Aurora PostgreSQL cluster in this region (password managed by Secrets Manager).<br/>global\_primary   the writer cluster of an Aurora Global Database; also creates the global cluster.<br/>global\_secondary a read-only cluster in another region, attached to global\_cluster\_identifier. Apply the primary first. | `string` | `"standalone"` | no |
| <a name="input_source_region"></a> [source\_region](#input\_source\_region) | global\_secondary only: the primary cluster's region. AWS needs it to copy the encrypted storage across regions. | `string` | `""` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnets for the DB subnet group (at least two, in different AZs; use the database subnets). | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource | `map(string)` | `{}` | no |
| <a name="input_team_name"></a> [team\_name](#input\_team\_name) | Team or tenant that owns this database | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC to place the cluster security group in. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | Aurora cluster ARN |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Aurora cluster identifier in this region |
| <a name="output_global_cluster_identifier"></a> [global\_cluster\_identifier](#output\_global\_cluster\_identifier) | Global cluster to pass to the secondary region's stack. Empty in standalone mode. |
| <a name="output_master_secret_arn"></a> [master\_secret\_arn](#output\_master\_secret\_arn) | Secrets Manager ARN of the master credentials: RDS-managed (standalone) or module-created (global\_primary). Empty on a secondary. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Load-balanced read-only endpoint |
| <a name="output_writer_endpoint"></a> [writer\_endpoint](#output\_writer\_endpoint) | Cluster (writer) endpoint. On a global\_secondary it is read-only until that cluster is promoted. |
<!-- END_TF_DOCS -->
