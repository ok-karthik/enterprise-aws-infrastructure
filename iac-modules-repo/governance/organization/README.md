# governance/organization

**Status:** 📝 Plan-only (wired into `foundation-live-repo`; not applied to AWS)

The AWS Organization foundation, applied from the **management account** by the owner: the organization itself (trusted service access and policy types), the OU tree, and the baseline SCP guardrails.

- **OUs** come from `var.organizational_units` (two levels). Default: Security, Infrastructure, Workloads (with Prod and NonProd), Sandbox, Policy-Staging, Suspended. Output `organizational_unit_ids` is a map of OU name to ID, used by `account-factory` and the bootstrap StackSets.
- **Generic guardrails** (SCPs), attached per-policy via `var.policy_targets` (Pattern A) or falling back to `var.guardrail_target_ous`, which **defaults to `Policy-Staging` only** (test on throw-away accounts before widening to `Sandbox`, `NonProd`, or `Prod`): deny leaving the organization; deny stopping/deleting CloudTrail; deny actions as the account's literal root user; deny disabling Config/GuardDuty/Security Hub/Access Analyzer/Macie; deny creating IAM users/login profiles/access keys (except from a break-glass session); protect `platform-*`/`github-actions-*` roles, the GitHub OIDC provider and `tg-state-*` buckets (except StackSets and break-glass); require IMDSv2 on `ec2:RunInstances`; deny creating an IAM role without the `platform-workload-boundary` permissions boundary. SCPs never apply to the management account, and SCPs cannot use a `Principal`/`NotPrincipal` element at all, so every exception here is a `Condition` matching an assumed-role ARN pattern (`var.break_glass_role_arn_pattern`), not a principal block.
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
| [aws_organizations_policy.backup_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
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
| [aws_organizations_policy.tag_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.backup_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.deny_unapproved_regions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.sandbox_guardrails](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.suspended_deny_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |
| [aws_organizations_policy_attachment.tag_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_region_exempt_actions"></a> [additional\_region\_exempt\_actions](#input\_additional\_region\_exempt\_actions) | Extra IAM actions to exempt from every region SCP (added to the built-in global-service list), e.g. ["ec2:DescribeRegions"]. | `list(string)` | `[]` | no |
| <a name="input_allowed_regions_by_ou"></a> [allowed\_regions\_by\_ou](#input\_allowed\_regions\_by\_ou) | Regions each OU may use (PLAN 4.6), keyed by OU name; matches \_config/regions.hcl's allowed\_regions\_by\_ou.<br/>One region SCP per key, attached only to that OU: an OU with no entry (or an empty list) gets no region<br/>SCP from this module at all. Starts empty by default so nothing widens past guardrail\_target\_ous without<br/>a deliberate choice by the caller (the live envcommon passes only the OUs it wants tested). | `map(list(string))` | `{}` | no |
| <a name="input_aws_service_access_principals"></a> [aws\_service\_access\_principals](#input\_aws\_service\_access\_principals) | AWS services that may integrate with the organization (trusted access). AUTHORITATIVE: any principal<br/>enabled by hand and missing here is disabled on apply, so check the plan. The default keeps the StackSets<br/>access that bootstrap.sh enables and adds what PLAN phases 2 to 6 need. | `list(string)` | <pre>[<br/>  "member.org.stacksets.cloudformation.amazonaws.com",<br/>  "sso.amazonaws.com",<br/>  "account.amazonaws.com",<br/>  "iam.amazonaws.com",<br/>  "access-analyzer.amazonaws.com",<br/>  "cloudtrail.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "config-multiaccountsetup.amazonaws.com",<br/>  "guardduty.amazonaws.com",<br/>  "securityhub.amazonaws.com",<br/>  "inspector2.amazonaws.com",<br/>  "macie.amazonaws.com",<br/>  "auditmanager.amazonaws.com",<br/>  "backup.amazonaws.com",<br/>  "tagpolicies.tag.amazonaws.com",<br/>  "ram.amazonaws.com",<br/>  "ipam.amazonaws.com",<br/>  "fms.amazonaws.com"<br/>]</pre> | no |
| <a name="input_backup_policy_delete_after_days"></a> [backup\_policy\_delete\_after\_days](#input\_backup\_policy\_delete\_after\_days) | Retention period in days for daily backups created by the organization Backup Policy. | `number` | `35` | no |
| <a name="input_backup_policy_regions"></a> [backup\_policy\_regions](#input\_backup\_policy\_regions) | Target regions for backup plan execution in the organization Backup Policy. | `list(string)` | <pre>[<br/>  "eu-central-1",<br/>  "eu-west-1"<br/>]</pre> | no |
| <a name="input_break_glass_role_arn_pattern"></a> [break\_glass\_role\_arn\_pattern](#input\_break\_glass\_role\_arn\_pattern) | ARN pattern (StringLike) matching a BreakGlassAdmin session, used as an exception in the guardrails that<br/>name one (deny\_iam\_user\_creation, protect\_platform\_resources). Matches the Identity Center permission set<br/>role naming that security/break-glass-alerts also matches (role\_glob there). | `string` | `"arn:*:sts::*:assumed-role/AWSReservedSSO_BreakGlassAdmin_*/*"` | no |
| <a name="input_delegated_administrators"></a> [delegated\_administrators](#input\_delegated\_administrators) | Delegated administrator accounts: service principal => account id, for example<br/>{ "access-analyzer.amazonaws.com" = "<security-tooling account id>" }. Each service needs trusted access in<br/>aws\_service\_access\_principals. Leave a service out until its account really exists (no placeholder ids). | `map(string)` | `{}` | no |
| <a name="input_enable_backup_policy"></a> [enable\_backup\_policy](#input\_enable\_backup\_policy) | Enable organization Backup Policy enforcing daily backups for resources tagged backup=true (PLAN 4.6). | `bool` | `false` | no |
| <a name="input_enable_centralized_root_access"></a> [enable\_centralized\_root\_access](#input\_enable\_centralized\_root\_access) | Enable centralized root access management (RootCredentialsManagement and RootSessions), so member accounts need no root credentials. See docs/IDENTITY.md. | `bool` | `true` | no |
| <a name="input_enable_sandbox_guardrails"></a> [enable\_sandbox\_guardrails](#input\_enable\_sandbox\_guardrails) | Attach the Sandbox-only guardrails (deny large instance families, deny RI/Savings Plan purchases) to the Sandbox OU. Off by default: the Sandbox account is the owner's free-experimentation zone (learning-plan labs), turned on deliberately. | `bool` | `false` | no |
| <a name="input_enable_suspended_deny_all"></a> [enable\_suspended\_deny\_all](#input\_enable\_suspended\_deny\_all) | Attach a deny-everything SCP to the Suspended OU. Safe by construction: the OU starts empty, so this has no effect until an account is actually moved there. | `bool` | `true` | no |
| <a name="input_enable_tag_policy"></a> [enable\_tag\_policy](#input\_enable\_tag\_policy) | Enable organization Tag Policy enforcing standard tags on taggable resources (PLAN 4.6). | `bool` | `false` | no |
| <a name="input_enabled_policy_types"></a> [enabled\_policy\_types](#input\_enabled\_policy\_types) | Policy types enabled on the organization root. Must include SERVICE\_CONTROL\_POLICY. | `list(string)` | <pre>[<br/>  "SERVICE_CONTROL_POLICY",<br/>  "RESOURCE_CONTROL_POLICY",<br/>  "TAG_POLICY",<br/>  "BACKUP_POLICY",<br/>  "DECLARATIVE_POLICY_EC2"<br/>]</pre> | no |
| <a name="input_guardrail_target_ous"></a> [guardrail\_target\_ous](#input\_guardrail\_target\_ous) | Default OUs the baseline SCP guardrails are attached to when not overridden in policy\_targets. Starts<br/>with Policy-Staging only, so a new SCP is tested on throw-away accounts before it can lock real ones<br/>out (PLAN 4.6). Widen it deliberately, for example ["Policy-Staging", "Sandbox", "NonProd"], then the rest. | `list(string)` | <pre>[<br/>  "Policy-Staging"<br/>]</pre> | no |
| <a name="input_organizational_units"></a> [organizational\_units](#input\_organizational\_units) | The OU tree, two levels deep. Key = OU name. `parent` is null for a top-level OU (directly under the<br/>root) or the name of a top-level OU. Default is the target layout of PLAN.md: Security and<br/>Infrastructure, Workloads with Prod and NonProd, Sandbox, Policy-Staging (test SCPs here first) and<br/>Suspended (accounts waiting to be closed). | <pre>map(object({<br/>    parent = optional(string)<br/>  }))</pre> | <pre>{<br/>  "Infrastructure": {},<br/>  "NonProd": {<br/>    "parent": "Workloads"<br/>  },<br/>  "Policy-Staging": {},<br/>  "Prod": {<br/>    "parent": "Workloads"<br/>  },<br/>  "Sandbox": {},<br/>  "Security": {},<br/>  "Suspended": {},<br/>  "Workloads": {}<br/>}</pre> | no |
| <a name="input_policy_targets"></a> [policy\_targets](#input\_policy\_targets) | Per-policy target OU mapping, allowing progressive per-policy rollouts across OUs (Pattern A).<br/>Key = guardrail policy key (e.g. deny\_leave\_org, require\_imdsv2).<br/>Value = list of OU names where this specific policy should be attached.<br/>If a policy key is omitted from this map, it defaults to var.guardrail\_target\_ous. | `map(list(string))` | `{}` | no |
| <a name="input_tag_policy_allowed_data_classifications"></a> [tag\_policy\_allowed\_data\_classifications](#input\_tag\_policy\_allowed\_data\_classifications) | Allowed values for the DataClassification tag enforced by the Tag Policy. | `list(string)` | <pre>[<br/>  "public",<br/>  "internal",<br/>  "confidential",<br/>  "restricted"<br/>]</pre> | no |
| <a name="input_tag_policy_allowed_environments"></a> [tag\_policy\_allowed\_environments](#input\_tag\_policy\_allowed\_environments) | Allowed values for the Environment tag enforced by the Tag Policy. | `list(string)` | <pre>[<br/>  "dev",<br/>  "staging",<br/>  "prod",<br/>  "global"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_backup_policy_id"></a> [backup\_policy\_id](#output\_backup\_policy\_id) | ID of the Platform Backup Policy, or null when enable\_backup\_policy is false |
| <a name="output_centralized_root_access_enabled"></a> [centralized\_root\_access\_enabled](#output\_centralized\_root\_access\_enabled) | Whether centralized root access management is enabled |
| <a name="output_delegated_administrators"></a> [delegated\_administrators](#output\_delegated\_administrators) | Delegated administrator accounts, keyed by service principal |
| <a name="output_effective_policy_targets"></a> [effective\_policy\_targets](#output\_effective\_policy\_targets) | Effective target OUs for each guardrail policy |
| <a name="output_guardrail_policy_ids"></a> [guardrail\_policy\_ids](#output\_guardrail\_policy\_ids) | Map of guardrail name to SCP ID |
| <a name="output_management_account_id"></a> [management\_account\_id](#output\_management\_account\_id) | Account ID of the management account |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | ID of the AWS Organization (o-...) |
| <a name="output_organizational_unit_ids"></a> [organizational\_unit\_ids](#output\_organizational\_unit\_ids) | Map of OU name to OU ID (ou-...) |
| <a name="output_region_policy_ids"></a> [region\_policy\_ids](#output\_region\_policy\_ids) | Map of OU name to that OU's region SCP ID (only the OUs that have one, PLAN 4.6) |
| <a name="output_root_id"></a> [root\_id](#output\_root\_id) | ID of the organization root (r-...) |
| <a name="output_sandbox_guardrails_policy_id"></a> [sandbox\_guardrails\_policy\_id](#output\_sandbox\_guardrails\_policy\_id) | ID of the Sandbox-only guardrail SCP, or null when enable\_sandbox\_guardrails is false |
| <a name="output_suspended_deny_all_policy_id"></a> [suspended\_deny\_all\_policy\_id](#output\_suspended\_deny\_all\_policy\_id) | ID of the Suspended deny-all SCP, or null when enable\_suspended\_deny\_all is false |
| <a name="output_tag_policy_id"></a> [tag\_policy\_id](#output\_tag\_policy\_id) | ID of the Platform Tag Policy, or null when enable\_tag\_policy is false |
<!-- END_TF_DOCS -->
