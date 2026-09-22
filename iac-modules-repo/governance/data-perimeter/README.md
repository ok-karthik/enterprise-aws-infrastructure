# governance/data-perimeter

**Resource Control Policies** (RCPs, PLAN 4.6): deny access to a resource from any principal **outside this organization**, and require TLS. Applied from the **management account**, the same way SCPs are.

RCPs work from the resource's side: a permissive bucket, key, queue or secret policy no longer matters for the accounts this is attached to, because the RCP still denies the request. This closes the PLAN 3.7 gap where `sqs:SetQueueAttributes` / `sns:SetTopicAttributes` could set a queue or topic policy that grants access to an outside principal, bypassing the Developer policy's `AddPermission` deny — for SQS. **SNS is not covered**: at the time this module was written, RCPs do not support SNS. Check the current AWS documentation; until SNS support exists (or is confirmed absent), the PLAN 3.7 second follow-up (an SCP or Config rule for SNS) is still open.

## Services (`var.enabled_services`)

| Service | Default | Risk |
|---|---|---|
| `s3`, `kms`, `sqs`, `secretsmanager` | **on** | Low: only denies access from outside the organization. Nothing legitimate inside this platform needs that. |
| `sts` | **off** | High: an RCP on STS also covers the actions that create the organization's **first** session — GitHub Actions OIDC (`sts:AssumeRoleWithWebIdentity`) and IAM Identity Center SAML federation (`sts:AssumeRoleWithSAML`). Those callers have no `aws:PrincipalOrgID` **yet**, because they are how a principal joins the org's identity in the first place. `var.sts_federation_exempt_actions` (default: both of those) is subtracted from an explicit list of STS actions — RCPs cannot use `Action = "sts:*"` together with an exemption (`Action` and `NotAction` cannot both appear in one statement, and `NotAction` alone would reach far past STS). Turn `sts` on only after `s3`/`kms`/`sqs`/`secretsmanager` have been proven on Policy-Staging, and confirm CI and sign-in still work before widening past it. |

## Attachment (`var.target_ous`, `var.target_ou_ids`)

Starts with **Policy-Staging only**, same reasoning as `governance/organization`'s `guardrail_target_ous`. This module does not own the OU tree (that's `governance/organization`), so it takes `target_ou_ids` — the OU name → ID map — as an input, normally `governance/organization`'s `organizational_unit_ids` output via a Terragrunt dependency.

## Not verified offline

- That RCPs actually support exactly `s3`, `kms`, `sqs`, `secretsmanager` (and not yet `sns`) at apply time — check the current AWS documentation before widening `enabled_services`.
- That `sts:AssumeRoleWithSAML` / `AssumeRoleWithWebIdentity` are the complete and correct set of "no org membership yet" actions for this platform's actual identity providers.
- The full, current list of STS actions (`local.all_sts_actions`): AWS may add new ones after this module was written.

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
| [aws_organizations_policy.data_perimeter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.data_perimeter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_enabled_services"></a> [enabled\_services](#input\_enabled\_services) | Which services get a data-perimeter RCP. s3, kms, sqs and secretsmanager are the low-risk ones: they only<br/>deny access from OUTSIDE the organization, which nothing legitimate inside the platform needs. sts is<br/>NOT enabled by default: an RCP on STS also covers the identity-federation actions that create the<br/>org's first session (GitHub OIDC, SAML into Identity Center) - see the README before adding it, and<br/>widen it last, after s3/kms/sqs/secretsmanager have been proven on Policy-Staging. | `list(string)` | <pre>[<br/>  "s3",<br/>  "kms",<br/>  "sqs",<br/>  "secretsmanager"<br/>]</pre> | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | ID of the AWS Organization (o-xxxxxxxxxx). Every RCP denies access from any principal outside it. | `string` | n/a | yes |
| <a name="input_sts_federation_exempt_actions"></a> [sts\_federation\_exempt\_actions](#input\_sts\_federation\_exempt\_actions) | STS actions exempt from the organization-membership check, because the caller has no aws:PrincipalOrgID<br/>until AFTER the action succeeds (it is how they join the org's identity in the first place):<br/>AssumeRoleWithWebIdentity (GitHub Actions OIDC) and AssumeRoleWithSAML (IAM Identity Center federation from<br/>the IdP). Only used when "sts" is in enabled\_services. Denying these outright would lock out CI and human<br/>sign-in. | `list(string)` | <pre>[<br/>  "sts:AssumeRoleWithWebIdentity",<br/>  "sts:AssumeRoleWithSAML"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_target_ou_ids"></a> [target\_ou\_ids](#input\_target\_ou\_ids) | OU name => OU id (governance/organization's organizational\_unit\_ids output), for the OUs in var.target\_ous.<br/>This module does not own the OU tree, so it takes the ids as an input rather than re-deriving them. | `map(string)` | n/a | yes |
| <a name="input_target_ous"></a> [target\_ous](#input\_target\_ous) | OUs each RCP is attached to. Starts with Policy-Staging only (PLAN 4.6, same reasoning as governance/organization's guardrail\_target\_ous): test on throw-away accounts before widening it. Every entry must be a key of var.target\_ou\_ids. | `list(string)` | <pre>[<br/>  "Policy-Staging"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_rcp_ids"></a> [rcp\_ids](#output\_rcp\_ids) | Map of service short name to its RCP's policy ID |
<!-- END_TF_DOCS -->
