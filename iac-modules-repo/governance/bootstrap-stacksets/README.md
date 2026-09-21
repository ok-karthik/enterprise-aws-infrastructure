# governance/bootstrap-stacksets

Rolls the Day-0 bootstrap template (`foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml`: state bucket, GitHub OIDC provider, `github-actions-plan` / `github-actions-apply` roles and boundary) out to **every member account** in the targeted OUs, with no human step when a new account joins. Service-managed StackSets with auto-deployment on; stacks are retained if an account leaves or an instance is removed.

- **One StackSet per GitHub Environment.** The environment sets the apply role's trust subject, and auto-deployment can only use the StackSet's own parameters, so a single StackSet cannot serve dev, prod and core. Typical: `bootstrap-nonprod` (NonProd OU, `dev`), `bootstrap-prod` (Prod OU, `prod`), `bootstrap-core` (Security + Infrastructure OUs, `core`). Sandbox and Suspended are not targeted.
- **Names must start with `bootstrap-`.** The apply role's permissions boundary protects stacks named `StackSet-bootstrap-*`.
- **`AllowOrganizationsAdmin` is fixed to `"false"`** for member accounts, so the boundary denies `organizations:*` and `account:*` there. `policies/terraform/deny_member_org_admin.rego` fails any plan that changes this.
- **The template body is an input**, so the module has no file paths. The live leaf (`foundation-live-repo/_global/governance/bootstrap-stacksets`) passes `file(...)`.
- **Prerequisites** (done by `foundation-live-repo/_bootstrap/bootstrap.sh`): AWS Organizations with all features, and StackSets trusted access enabled. Applied from the management account, by the owner.
- **Do not move an account between OUs targeted by different StackSets.** Its stack would be deleted and re-created, and the create fails on the retained state bucket name. Accounts must not move between Prod and NonProd.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudformation_stack_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set) | resource |
| [aws_cloudformation_stack_set_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | GitHub repository (owner/name) whose jobs may assume the CI roles in member accounts. | `string` | `"ok-karthik/enterprise-aws-infrastructure"` | no |
| <a name="input_noncurrent_version_days"></a> [noncurrent\_version\_days](#input\_noncurrent\_version\_days) | Days before old versions of state files are deleted in each member account's state bucket. | `number` | `90` | no |
| <a name="input_region"></a> [region](#input\_region) | Region the stack instances are deployed to. Primary region only: the state bucket and roles are regional/global and the secondary region comes later. | `string` | `"eu-central-1"` | no |
| <a name="input_stack_sets"></a> [stack\_sets](#input\_stack\_sets) | One service-managed StackSet per GitHub Environment, keyed by StackSet name. The name must start<br/>with "bootstrap-": the apply role's permissions boundary only protects stacks named<br/>StackSet-bootstrap-*. The GitHub Environment is a StackSet parameter (it sets the apply role's<br/>trust subject), and auto-deployment can only use the StackSet's own parameters, which is why each<br/>environment needs its own StackSet.<br/>  github\_environment      the GitHub Environment allowed to assume github-actions-apply (dev, prod, core, ...)<br/>  organizational\_unit\_ids OUs (ou-...) whose accounts get the stack, now and when they join later | <pre>map(object({<br/>    github_environment      = string<br/>    organizational_unit_ids = list(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags set on each StackSet. CloudFormation propagates them to every resource the stacks create in the member accounts. | `map(string)` | `{}` | no |
| <a name="input_template_body"></a> [template\_body](#input\_template\_body) | Body of the account-bootstrap CloudFormation template. The live leaf reads foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml, so this module stays free of file paths. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_github_environments"></a> [github\_environments](#output\_github\_environments) | GitHub Environment each StackSet trusts for github-actions-apply, keyed by StackSet name |
| <a name="output_stack_set_arns"></a> [stack\_set\_arns](#output\_stack\_set\_arns) | ARNs of the bootstrap StackSets, keyed by name |
| <a name="output_stack_set_names"></a> [stack\_set\_names](#output\_stack\_set\_names) | Names of the bootstrap StackSets, keyed by name |
<!-- END_TF_DOCS -->
