# identity/identity-center

IAM Identity Center for humans, applied from the **management account**: the permission-set catalog, the groups, and the account assignments **OU → group → permission set**, expanded to accounts with the account registry. The IdP (Okta / Entra ID / Google) and SCIM are set up by hand: see [`docs/IDENTITY.md`](../../../docs/IDENTITY.md).

**Catalog:** `ReadOnly`, `Developer`, `PlatformEngineer`, `SecurityAudit`, `Billing`, `BreakGlassAdmin`. Sessions are 1 hour for the elevated sets (`PlatformEngineer`, `BreakGlassAdmin`) and 8 hours for the rest.

- **No standing admin.** `AdministratorAccess` is only in `BreakGlassAdmin`, which cannot be assigned statically (`allow_static_break_glass` is a deliberate exception). `PlatformEngineer` is PowerUser plus IAM on `role/platform/*` only, only for roles that carry `platform-workload-boundary`, and it cannot attach admin policies.
- **Just in time in Prod.** Elevated sets cannot be assigned statically in the OUs in `jit_only_ous` (Prod); use [`docs/BREAK_GLASS.md`](../../../docs/BREAK_GLASS.md). `Developer` is only assignable in `developer_ous` (NonProd, Sandbox, Policy-Staging); use `ReadOnly` in Prod.
- **Developer** = customer-managed policy `platform-developer` + permissions boundary `platform-workload-boundary`, both attached **by name**: they must exist in every assigned account, which `governance/account-baseline` guarantees.
- **ABAC:** `team` and `cost_center` become session tags (`aws:PrincipalTag/...`). The attribute paths depend on the IdP (`abac_attributes`).
- **Groups** are read from the SCIM-synced identity store by default (names must match the IdP exactly); `manage_groups = true` creates them when there is no external IdP.
- Only accounts with a real id are assignable; registry placeholders are refused.

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
| [aws_identitystore_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_ssoadmin_account_assignment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_customer_managed_policy_attachment.developer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_customer_managed_policy_attachment) | resource |
| [aws_ssoadmin_instance_access_control_attributes.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_instance_access_control_attributes) | resource |
| [aws_ssoadmin_managed_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set_inline_policy.platform_engineer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set_inline_policy) | resource |
| [aws_ssoadmin_permissions_boundary_attachment.developer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permissions_boundary_attachment) | resource |
| [aws_identitystore_group.scim](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_group) | data source |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abac_attributes"></a> [abac\_attributes](#input\_abac\_attributes) | Attributes for access control (ABAC): session tag name => IdP attribute path. The tags become<br/>aws:PrincipalTag/<name> in every session, for example `team` and `cost_center` (used by the Developer<br/>policy to scope EC2 by team). The paths depend on your IdP's SCIM attributes: check them before applying. | `map(string)` | <pre>{<br/>  "cost_center": "${path:enterprise.costCenter}",<br/>  "team": "${path:enterprise.department}"<br/>}</pre> | no |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Accounts that can be assigned, from the account registry: name => { id, ou }. Pass only accounts with a real account id. | <pre>map(object({<br/>    id = string<br/>    ou = string<br/>  }))</pre> | `{}` | no |
| <a name="input_allow_static_break_glass"></a> [allow\_static\_break\_glass](#input\_allow\_static\_break\_glass) | Allow BreakGlassAdmin in var.assignments. Off by default: break-glass access is just-in-time. | `bool` | `false` | no |
| <a name="input_assignments"></a> [assignments](#input\_assignments) | Who gets what where: OU name => group name => permission set names. Expanded to every account in that OU<br/>using var.accounts. The management account has the OU name "Root". Example:<br/>  { NonProd = { developers = ["Developer"] }, Prod = { developers = ["ReadOnly"] } } | `map(map(list(string)))` | `{}` | no |
| <a name="input_developer_ous"></a> [developer\_ous](#input\_developer\_ous) | OUs where the Developer permission set may be assigned. | `list(string)` | <pre>[<br/>  "NonProd",<br/>  "Sandbox",<br/>  "Policy-Staging"<br/>]</pre> | no |
| <a name="input_developer_policy_name"></a> [developer\_policy\_name](#input\_developer\_policy\_name) | Name of the customer-managed policy in every account that the Developer permission set attaches (created by governance/account-baseline). | `string` | `"platform-developer"` | no |
| <a name="input_elevated_permission_sets"></a> [elevated\_permission\_sets](#input\_elevated\_permission\_sets) | Permission sets that can change IAM or everything. They get 1-hour sessions and cannot be assigned statically in jit\_only\_ous. | `list(string)` | <pre>[<br/>  "PlatformEngineer",<br/>  "BreakGlassAdmin"<br/>]</pre> | no |
| <a name="input_groups"></a> [groups](#input\_groups) | Names of the groups assigned to accounts. With an external IdP (Okta, Entra ID, Google) the groups are synced<br/>by SCIM and only READ here (manage\_groups = false); the names must match the IdP group display names exactly. | `list(string)` | `[]` | no |
| <a name="input_jit_only_ous"></a> [jit\_only\_ous](#input\_jit\_only\_ous) | OUs where elevated permission sets are only granted just in time. | `list(string)` | <pre>[<br/>  "Prod"<br/>]</pre> | no |
| <a name="input_manage_groups"></a> [manage\_groups](#input\_manage\_groups) | Create the groups in the Identity Center identity store. Leave false with an external IdP: SCIM owns the groups and Terraform only looks them up. | `bool` | `false` | no |
| <a name="input_session_durations"></a> [session\_durations](#input\_session\_durations) | Session length per permission set (ISO 8601). 1 hour for the elevated sets, 8 hours for the rest. | `map(string)` | <pre>{<br/>  "Billing": "PT8H",<br/>  "BreakGlassAdmin": "PT1H",<br/>  "Developer": "PT8H",<br/>  "PlatformEngineer": "PT1H",<br/>  "ReadOnly": "PT8H",<br/>  "SecurityAudit": "PT8H"<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_workload_boundary_name"></a> [workload\_boundary\_name](#input\_workload\_boundary\_name) | Name of the permissions boundary in every account (created by governance/account-baseline). The Developer set is capped by it, and PlatformEngineer can only create roles that carry it. | `string` | `"platform-workload-boundary"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_assignment_keys"></a> [assignment\_keys](#output\_assignment\_keys) | Every account/group/permission-set assignment that exists |
| <a name="output_group_ids"></a> [group\_ids](#output\_group\_ids) | Map of group name to identity store group ID |
| <a name="output_identity_store_id"></a> [identity\_store\_id](#output\_identity\_store\_id) | ID of the Identity Center identity store |
| <a name="output_instance_arn"></a> [instance\_arn](#output\_instance\_arn) | ARN of the IAM Identity Center instance |
| <a name="output_permission_set_arns"></a> [permission\_set\_arns](#output\_permission\_set\_arns) | Map of permission set name to ARN |
<!-- END_TF_DOCS -->
