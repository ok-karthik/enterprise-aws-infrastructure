# governance/organization

The AWS Organization foundation, applied from the **management account** by the owner: the organization itself (trusted service access and policy types), the OU tree, and the baseline SCP guardrails.

- **OUs** come from `var.organizational_units` (two levels). Default: Security, Infrastructure, Workloads (with Prod and NonProd), Sandbox, Policy-Staging, Suspended. Output `organizational_unit_ids` is a map of OU name to ID, used by `account-factory` and the bootstrap StackSets.
- **Guardrails** (SCPs): deny leaving the organization, deny stopping/deleting CloudTrail, deny requests outside `allowed_regions` (global services exempt). They attach to `guardrail_target_ous`, which **defaults to `Policy-Staging` only**: test a policy on throw-away accounts before widening it. SCPs never apply to the management account.
- **Authoritative lists.** `aws_service_access_principals` and `enabled_policy_types` are managed exactly: anything enabled by hand and not in the list is *disabled* on apply. The default list keeps StackSets access (needed by the bootstrap StackSets) and Identity Center. Read the plan.
- **The organization already exists** (`bootstrap.sh` creates it). Import it, and any OU you made by hand, before the first apply; the live leaf lists the exact commands.
- ACK cross-account trust used to live here and is now the separate `identity/ack-cross-account` module (it is applied per account, not in management).

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
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization) | resource |
| [aws_organizations_organizational_unit.child](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_organizational_unit.top](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_policy.deny_disable_cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_leave_org](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_unapproved_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_region_exempt_actions"></a> [additional\_region\_exempt\_actions](#input\_additional\_region\_exempt\_actions) | Extra IAM actions to exempt from the region SCP (added to the built-in global-service list), e.g. ["ec2:DescribeRegions"]. | `list(string)` | `[]` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions workloads may use. The region SCP denies every request to a region not in this list (global services are exempt). | `list(string)` | <pre>[<br/>  "eu-central-1"<br/>]</pre> | no |
| <a name="input_aws_service_access_principals"></a> [aws\_service\_access\_principals](#input\_aws\_service\_access\_principals) | AWS services that may integrate with the organization (trusted access). AUTHORITATIVE: any principal<br/>enabled by hand and missing here is disabled on apply, so check the plan. The default keeps the StackSets<br/>access that bootstrap.sh enables and adds what PLAN phases 2 to 6 need. | `list(string)` | <pre>[<br/>  "member.org.stacksets.cloudformation.amazonaws.com",<br/>  "sso.amazonaws.com",<br/>  "account.amazonaws.com",<br/>  "iam.amazonaws.com",<br/>  "access-analyzer.amazonaws.com",<br/>  "cloudtrail.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "guardduty.amazonaws.com",<br/>  "securityhub.amazonaws.com",<br/>  "inspector2.amazonaws.com",<br/>  "macie.amazonaws.com",<br/>  "backup.amazonaws.com",<br/>  "tagpolicies.tag.amazonaws.com",<br/>  "ram.amazonaws.com",<br/>  "ipam.amazonaws.com",<br/>  "fms.amazonaws.com"<br/>]</pre> | no |
| <a name="input_enabled_policy_types"></a> [enabled\_policy\_types](#input\_enabled\_policy\_types) | Policy types enabled on the organization root. Must include SERVICE\_CONTROL\_POLICY. | `list(string)` | <pre>[<br/>  "SERVICE_CONTROL_POLICY",<br/>  "RESOURCE_CONTROL_POLICY",<br/>  "TAG_POLICY",<br/>  "BACKUP_POLICY",<br/>  "DECLARATIVE_POLICY_EC2"<br/>]</pre> | no |
| <a name="input_guardrail_target_ous"></a> [guardrail\_target\_ous](#input\_guardrail\_target\_ous) | OUs the baseline SCP guardrails are attached to. Starts with Policy-Staging only, so a new SCP is tested on<br/>throw-away accounts before it can lock real ones out (PLAN 4.6). Widen it deliberately, for example<br/>["Policy-Staging", "Sandbox", "NonProd"], then the rest. | `list(string)` | <pre>[<br/>  "Policy-Staging"<br/>]</pre> | no |
| <a name="input_organizational_units"></a> [organizational\_units](#input\_organizational\_units) | The OU tree, two levels deep. Key = OU name. `parent` is null for a top-level OU (directly under the<br/>root) or the name of a top-level OU. Default is the target layout of PLAN.md: Security and<br/>Infrastructure, Workloads with Prod and NonProd, Sandbox, Policy-Staging (test SCPs here first) and<br/>Suspended (accounts waiting to be closed). | <pre>map(object({<br/>    parent = optional(string)<br/>  }))</pre> | <pre>{<br/>  "Infrastructure": {},<br/>  "NonProd": {<br/>    "parent": "Workloads"<br/>  },<br/>  "Policy-Staging": {},<br/>  "Prod": {<br/>    "parent": "Workloads"<br/>  },<br/>  "Sandbox": {},<br/>  "Security": {},<br/>  "Suspended": {},<br/>  "Workloads": {}<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_guardrail_policy_ids"></a> [guardrail\_policy\_ids](#output\_guardrail\_policy\_ids) | Map of guardrail name to SCP ID |
| <a name="output_management_account_id"></a> [management\_account\_id](#output\_management\_account\_id) | Account ID of the management account |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | ID of the AWS Organization (o-...) |
| <a name="output_organizational_unit_ids"></a> [organizational\_unit\_ids](#output\_organizational\_unit\_ids) | Map of OU name to OU ID (ou-...) |
| <a name="output_root_id"></a> [root\_id](#output\_root\_id) | ID of the organization root (r-...) |
<!-- END_TF_DOCS -->
