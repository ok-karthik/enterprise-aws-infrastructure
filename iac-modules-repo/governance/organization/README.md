# governance/organization

The AWS Organization foundation, applied from the **management account** by the owner: the organization itself (trusted service access and policy types), the OU tree, and the baseline SCP guardrails.

- **OUs** come from `var.organizational_units` (two levels). Default: Security, Infrastructure, Workloads (with Prod and NonProd), Sandbox, Policy-Staging, Suspended. Output `organizational_unit_ids` is a map of OU name to ID, used by `account-factory` and the bootstrap StackSets.
- **Generic guardrails** (SCPs), attached to `guardrail_target_ous`, which **defaults to `Policy-Staging` only** (test on throw-away accounts before widening it): deny leaving the organization; deny stopping/deleting CloudTrail; deny actions as the account's literal root user; deny disabling Config/GuardDuty/Security Hub/Access Analyzer/Macie; deny creating IAM users/login profiles/access keys (except from a break-glass session); protect `platform-*`/`github-actions-*` roles, the GitHub OIDC provider and `tg-state-*` buckets (except StackSets and break-glass); require IMDSv2 on `ec2:RunInstances`; deny creating an IAM role without the `platform-workload-boundary` permissions boundary. SCPs never apply to the management account, and SCPs cannot use a `Principal`/`NotPrincipal` element at all, so every exception here is a `Condition` matching an assumed-role ARN pattern (`var.break_glass_role_arn_pattern`), not a principal block.
- **Region SCPs, one per OU** (`var.allowed_regions_by_ou`, PLAN 4.6): each OU only gets a policy for itself, so a mistake in one OU's region list can never affect another. An OU with no entry (or an empty list) gets no region SCP. Starts empty by default.
- **Sandbox guardrails** (`var.enable_sandbox_guardrails`, default **off**): deny large instance families (8xlarge and up, bare metal) and Reserved Instance/Savings Plan purchases, attached only to the Sandbox OU. Off by default because Sandbox is the owner's free-experimentation account.
- **Suspended deny-all** (`var.enable_suspended_deny_all`, default **on**): denies everything, attached only to the Suspended OU. Safe by construction: that OU starts empty.
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
| [aws_iam_organizations_features.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_organizations_features) | resource |
| [aws_organizations_delegated_administrator.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator) | resource |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization) | resource |
| [aws_organizations_organizational_unit.child](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_organizational_unit.top](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_organizations_policy.deny_disable_cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_disable_detection_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_iam_user_creation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_leave_org](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_role_creation_without_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_root_user_actions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.deny_unapproved_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.protect_platform_resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.require_imdsv2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.sandbox_guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy.suspended_deny_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.deny_unapproved_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.sandbox_guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.suspended_deny_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_region_exempt_actions"></a> [additional\_region\_exempt\_actions](#input\_additional\_region\_exempt\_actions) | Extra IAM actions to exempt from every region SCP (added to the built-in global-service list), e.g. ["ec2:DescribeRegions"]. | `list(string)` | `[]` | no |
| <a name="input_allowed_regions_by_ou"></a> [allowed\_regions\_by\_ou](#input\_allowed\_regions\_by\_ou) | Regions each OU may use (PLAN 4.6), keyed by OU name; matches \_config/regions.hcl's allowed\_regions\_by\_ou.<br/>One region SCP per key, attached only to that OU: an OU with no entry (or an empty list) gets no region<br/>SCP from this module at all. Starts empty by default so nothing widens past guardrail\_target\_ous without<br/>a deliberate choice by the caller (the live envcommon passes only the OUs it wants tested). | `map(list(string))` | `{}` | no |
| <a name="input_aws_service_access_principals"></a> [aws\_service\_access\_principals](#input\_aws\_service\_access\_principals) | AWS services that may integrate with the organization (trusted access). AUTHORITATIVE: any principal<br/>enabled by hand and missing here is disabled on apply, so check the plan. The default keeps the StackSets<br/>access that bootstrap.sh enables and adds what PLAN phases 2 to 6 need. | `list(string)` | <pre>[<br/>  "member.org.stacksets.cloudformation.amazonaws.com",<br/>  "sso.amazonaws.com",<br/>  "account.amazonaws.com",<br/>  "iam.amazonaws.com",<br/>  "access-analyzer.amazonaws.com",<br/>  "cloudtrail.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "guardduty.amazonaws.com",<br/>  "securityhub.amazonaws.com",<br/>  "inspector2.amazonaws.com",<br/>  "macie.amazonaws.com",<br/>  "backup.amazonaws.com",<br/>  "tagpolicies.tag.amazonaws.com",<br/>  "ram.amazonaws.com",<br/>  "ipam.amazonaws.com",<br/>  "fms.amazonaws.com"<br/>]</pre> | no |
| <a name="input_break_glass_role_arn_pattern"></a> [break\_glass\_role\_arn\_pattern](#input\_break\_glass\_role\_arn\_pattern) | ARN pattern (StringLike) matching a BreakGlassAdmin session, used as an exception in the guardrails that<br/>name one (deny\_iam\_user\_creation, protect\_platform\_resources). Matches the Identity Center permission set<br/>role naming that security/break-glass-alerts also matches (role\_glob there). | `string` | `"arn:*:sts::*:assumed-role/AWSReservedSSO_BreakGlassAdmin_*/*"` | no |
| <a name="input_delegated_administrators"></a> [delegated\_administrators](#input\_delegated\_administrators) | Delegated administrator accounts: service principal => account id, for example<br/>{ "access-analyzer.amazonaws.com" = "<security-tooling account id>" }. Each service needs trusted access in<br/>aws\_service\_access\_principals. Leave a service out until its account really exists (no placeholder ids). | `map(string)` | `{}` | no |
| <a name="input_enable_centralized_root_access"></a> [enable\_centralized\_root\_access](#input\_enable\_centralized\_root\_access) | Enable centralized root access management (RootCredentialsManagement and RootSessions), so member accounts need no root credentials. See docs/ROOT\_ACCESS.md. | `bool` | `true` | no |
| <a name="input_enable_sandbox_guardrails"></a> [enable\_sandbox\_guardrails](#input\_enable\_sandbox\_guardrails) | Attach the Sandbox-only guardrails (deny large instance families, deny RI/Savings Plan purchases) to the Sandbox OU. Off by default: the Sandbox account is the owner's free-experimentation zone (learning-plan labs), turned on deliberately. | `bool` | `false` | no |
| <a name="input_enable_suspended_deny_all"></a> [enable\_suspended\_deny\_all](#input\_enable\_suspended\_deny\_all) | Attach a deny-everything SCP to the Suspended OU. Safe by construction: the OU starts empty, so this has no effect until an account is actually moved there. | `bool` | `true` | no |
| <a name="input_enabled_policy_types"></a> [enabled\_policy\_types](#input\_enabled\_policy\_types) | Policy types enabled on the organization root. Must include SERVICE\_CONTROL\_POLICY. | `list(string)` | <pre>[<br/>  "SERVICE_CONTROL_POLICY",<br/>  "RESOURCE_CONTROL_POLICY",<br/>  "TAG_POLICY",<br/>  "BACKUP_POLICY",<br/>  "DECLARATIVE_POLICY_EC2"<br/>]</pre> | no |
| <a name="input_guardrail_target_ous"></a> [guardrail\_target\_ous](#input\_guardrail\_target\_ous) | OUs the baseline SCP guardrails are attached to. Starts with Policy-Staging only, so a new SCP is tested on<br/>throw-away accounts before it can lock real ones out (PLAN 4.6). Widen it deliberately, for example<br/>["Policy-Staging", "Sandbox", "NonProd"], then the rest. | `list(string)` | <pre>[<br/>  "Policy-Staging"<br/>]</pre> | no |
| <a name="input_organizational_units"></a> [organizational\_units](#input\_organizational\_units) | The OU tree, two levels deep. Key = OU name. `parent` is null for a top-level OU (directly under the<br/>root) or the name of a top-level OU. Default is the target layout of PLAN.md: Security and<br/>Infrastructure, Workloads with Prod and NonProd, Sandbox, Policy-Staging (test SCPs here first) and<br/>Suspended (accounts waiting to be closed). | <pre>map(object({<br/>    parent = optional(string)<br/>  }))</pre> | <pre>{<br/>  "Infrastructure": {},<br/>  "NonProd": {<br/>    "parent": "Workloads"<br/>  },<br/>  "Policy-Staging": {},<br/>  "Prod": {<br/>    "parent": "Workloads"<br/>  },<br/>  "Sandbox": {},<br/>  "Security": {},<br/>  "Suspended": {},<br/>  "Workloads": {}<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_centralized_root_access_enabled"></a> [centralized\_root\_access\_enabled](#output\_centralized\_root\_access\_enabled) | Whether centralized root access management is enabled |
| <a name="output_delegated_administrators"></a> [delegated\_administrators](#output\_delegated\_administrators) | Delegated administrator accounts, keyed by service principal |
| <a name="output_guardrail_policy_ids"></a> [guardrail\_policy\_ids](#output\_guardrail\_policy\_ids) | Map of guardrail name to SCP ID |
| <a name="output_management_account_id"></a> [management\_account\_id](#output\_management\_account\_id) | Account ID of the management account |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | ID of the AWS Organization (o-...) |
| <a name="output_organizational_unit_ids"></a> [organizational\_unit\_ids](#output\_organizational\_unit\_ids) | Map of OU name to OU ID (ou-...) |
| <a name="output_region_policy_ids"></a> [region\_policy\_ids](#output\_region\_policy\_ids) | Map of OU name to that OU's region SCP ID (only the OUs that have one, PLAN 4.6) |
| <a name="output_root_id"></a> [root\_id](#output\_root\_id) | ID of the organization root (r-...) |
| <a name="output_sandbox_guardrails_policy_id"></a> [sandbox\_guardrails\_policy\_id](#output\_sandbox\_guardrails\_policy\_id) | ID of the Sandbox-only guardrail SCP, or null when enable\_sandbox\_guardrails is false |
| <a name="output_suspended_deny_all_policy_id"></a> [suspended\_deny\_all\_policy\_id](#output\_suspended\_deny\_all\_policy\_id) | ID of the Suspended deny-all SCP, or null when enable\_suspended\_deny\_all is false |
<!-- END_TF_DOCS -->
