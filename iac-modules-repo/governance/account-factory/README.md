# governance/account-factory

Creates and places the member accounts listed in the **account registry** (`foundation-live-repo/_config/accounts.hcl`), applied from the **management account** by the owner. Only registry entries with `create = true` are passed in, so placeholders and the management account are never vended.

- Each account is an `aws_organizations_account` with `close_on_deletion = false`, `lifecycle { prevent_destroy = true }` and IAM billing access allowed, placed in the OU named in the registry. **Terraform never closes an account.**
- **Safety:** the module refuses a `@example.com` email (the registry placeholder), a duplicate email and an unknown OU, so a wrong registry entry fails at plan time and never reaches the Organizations API.
- **Accounts you already created by hand must be imported** first (`terragrunt import 'aws_organizations_account.this["<name>"]' <account-id>`), see the live leaf.
- The account's root email cannot be changed lightly afterwards, and a new account starts with no bootstrap: the bootstrap StackSets (`governance/bootstrap-stacksets`) give it its state bucket and CI roles once its OU is targeted.

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
| [aws_organizations_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Member accounts to manage, keyed by account name (from the account registry, only the entries with<br/>create = true). `ou` is the name of an OU in var.ou\_ids. `email` is the account's root email and cannot be<br/>changed lightly afterwards. An account created by hand must be IMPORTED before the first apply. | <pre>map(object({<br/>    email = string<br/>    ou    = string<br/>  }))</pre> | n/a | yes |
| <a name="input_ou_ids"></a> [ou\_ids](#input\_ou\_ids) | Map of OU name to OU ID (the organization module's organizational\_unit\_ids output). | `map(string)` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the admin role AWS creates in each new account for the management account to assume. Only used when an account is created. | `string` | `"OrganizationAccountAccessRole"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_account_arns"></a> [account\_arns](#output\_account\_arns) | Map of account name to account ARN |
| <a name="output_account_ids"></a> [account\_ids](#output\_account\_ids) | Map of account name to account ID |
<!-- END_TF_DOCS -->
