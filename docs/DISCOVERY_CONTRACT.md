# Discovery contract

Tenant Terraform never hardcodes AWS IDs (VPC IDs, subnets, OIDC ARNs, cluster names, key ARNs). It reads them from SSM Parameter Store **in its own account** at plan time:

```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/platform/${var.env}/${var.region}/vpc/id"
}
```

SSM parameters live inside one account. When a VPC later sits in a network hub and is shared through RAM (Phase 5), a tenant cannot read the hub's parameters from its own account. So the **same parameter names are written into every workload account**, from the outputs of whatever stack owns the value. The names are the contract; where the resource lives can change without touching a tenant.

## Parameters

All under `/platform/<env>/<region>/`. `<env>` is `dev`, `staging`, `prod` or `global` (from the account's `env`), `<region>` the region the parameter is published for.

| Key | Value | Written by |
|---|---|---|
| `vpc/id` | The VPC ID | `governance/discovery-publisher` (from the VPC stack) |
| `vpc/database_subnets` | Comma-delimited database subnet IDs | `governance/discovery-publisher` (from the VPC stack) |
| `eks/cluster_name` | Name of the EKS cluster | `governance/discovery-publisher` (from the EKS stack) |
| `eks/oidc_provider_arn` | EKS OIDC provider ARN (IRSA / Pod Identity) | `governance/discovery-publisher` (from the EKS stack) |
| `ack/cross_account_role_arn` | ACK controller cross-account role ARN | `governance/discovery-publisher` (from `identity/ack-cross-account`, once present in the account) |
| `account/id` | The account's 12-digit ID | `governance/account-baseline` |
| `account/ou` | Name of the OU the account is in | `governance/account-baseline` |
| `kms/general_key_arn` | CMK for general (internal) data | `governance/account-baseline` |
| `kms/confidential_key_arn` | CMK for confidential data | `governance/account-baseline` |
| `iam/workload_boundary_arn` | `platform-workload-boundary`, which every role a tenant creates must carry | `governance/account-baseline` |

## Rules

- **One owner per name.** The VPC and EKS modules can still publish their own parameters (`publish_ssm_parameters`), but the live blueprints turn that off and let the publisher own them. Two resources with one name fail at apply.
- **Only contract keys.** `governance/discovery-publisher` rejects any other key, so a name cannot appear without being added here first (and to the module's validation).
- **Non-sensitive metadata only.** Parameters are plain `String`, readable by tenant pipelines. Never store secrets here (this is why Checkov `CKV2_AWS_34` is suppressed for them).
- **Adding a key** means: add it to this table, to the `parameters` validation of `governance/discovery-publisher`, and to whichever stack owns the value.
