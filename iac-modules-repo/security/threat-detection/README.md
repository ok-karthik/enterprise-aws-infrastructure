# security/threat-detection

Turns on **GuardDuty, Security Hub, Inspector v2 and Macie** for the whole organization (PLAN 4.4), applied in the `security-tooling` account, which is the **delegated administrator** for each service. Detective is optional.

Delegation itself is granted by `governance/organization`'s `delegated_administrators` map, applied from the management account — this module assumes it already happened.

## Regional services, applied in every allowed region

GuardDuty, Security Hub, Inspector v2 and Macie are regional. Apply this module once per region in `regions.hcl`'s allow-list, with `is_primary_region = true` in exactly one region (`_config/regions.hcl` `primary_region`). Two resources are **once-per-organization**, not once-per-region, and are only created when `is_primary_region = true`:

- The Security Hub **cross-region finding aggregator** (`linking_mode = "ALL_REGIONS"`), so every region's findings show up in the primary region.
- **Detective**, if `enable_detective = true`. A single graph, not one per region.

## What each service auto-enables

| Service | For this account | Organization-wide |
|---|---|---|
| GuardDuty | Detector, `guardduty_features` (default: S3 data events, EKS audit + runtime monitoring, EBS malware protection, RDS login events, Lambda network logs) | `auto_enable_organization_members` (default `ALL`) and the same features |
| Security Hub | Subscribed to `securityhub_standards` (default: FSBP, CIS v3) | `auto_enable = true`, `configuration_type = "LOCAL"` (each member manages its own subscription once enabled; no central configuration policy) |
| Inspector v2 | `inspector2_resource_types` (default EC2, ECR, Lambda) | Same resource types, auto-enabled |
| Macie | Enabled, `macie_finding_publishing_frequency` | `auto_enable = true` |
| Detective (optional) | — | `auto_enable = true`, once created |

## Not verified offline, and known limits

- That the delegated-administrator registration in `governance/organization` is enough for each service to accept these configurations (each API also does its own checks on top of the Organizations delegation).
- **Macie has no tag-based auto-enable.** PLAN 4.4 asked for "auto-discovery on accounts tagged confidential"; the Macie API's organization auto-enable is a single organization-wide boolean, with no per-account tag filter. `auto_enable = true` turns Macie on for every member; scoping it to confidential accounts only would need a custom automation (for example a Lambda reacting to account tag changes) that this module does not build.
- **Detective** requires GuardDuty to have been enabled in an account for at least 48 hours before Detective can invite it (per AWS); this cannot be tested offline.
- EKS runtime monitoring's `EKS_ADDON_MANAGEMENT` sub-feature installs and manages the GuardDuty EKS add-on itself; whether that conflicts with a cluster's own add-on management is worth checking on the first real EKS cluster.

## Cost

30-day free trials for GuardDuty, Security Hub, Inspector and Macie (see PLAN.md's apply-mode table); Detective has its own separate free trial. Put a reminder at day 25 to check the cost or disable them.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.65.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_detective_graph.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/detective_graph) | resource |
| [aws_detective_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/detective_organization_configuration) | resource |
| [aws_guardduty_detector.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector) | resource |
| [aws_guardduty_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration) | resource |
| [aws_guardduty_organization_configuration_feature.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_inspector2_enabler.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_enabler) | resource |
| [aws_inspector2_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_organization_configuration) | resource |
| [aws_macie2_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/macie2_account) | resource |
| [aws_macie2_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/macie2_organization_configuration) | resource |
| [aws_securityhub_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_account) | resource |
| [aws_securityhub_finding_aggregator.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_finding_aggregator) | resource |
| [aws_securityhub_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_configuration) | resource |
| [aws_securityhub_standards_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_standards_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_enable_detective"></a> [enable\_detective](#input\_enable\_detective) | Create an Amazon Detective behavior graph and auto-enable it organization-wide (needs GuardDuty enabled for at least 48 hours in an account before Detective can invite it, per AWS). | `bool` | `false` | no |
| <a name="input_enable_macie"></a> [enable\_macie](#input\_enable\_macie) | Enable Macie in this account and auto-enable it organization-wide. | `bool` | `true` | no |
| <a name="input_guardduty_auto_enable_organization_members"></a> [guardduty\_auto\_enable\_organization\_members](#input\_guardduty\_auto\_enable\_organization\_members) | ALL: every current and future member gets GuardDuty automatically. NEW: only accounts that join later. NONE: no auto-enable. | `string` | `"ALL"` | no |
| <a name="input_guardduty_features"></a> [guardduty\_features](#input\_guardduty\_features) | GuardDuty protection plans to auto-enable organization-wide. EKS\_RUNTIME\_MONITORING also turns on the EKS add-on management sub-feature, so GuardDuty manages the runtime agent add-on itself. | `list(string)` | <pre>[<br/>  "S3_DATA_EVENTS",<br/>  "EKS_AUDIT_LOGS",<br/>  "EKS_RUNTIME_MONITORING",<br/>  "EBS_MALWARE_PROTECTION",<br/>  "RDS_LOGIN_EVENTS",<br/>  "LAMBDA_NETWORK_LOGS"<br/>]</pre> | no |
| <a name="input_guardduty_finding_publishing_frequency"></a> [guardduty\_finding\_publishing\_frequency](#input\_guardduty\_finding\_publishing\_frequency) | How often GuardDuty exports findings to CloudWatch Events. | `string` | `"FIFTEEN_MINUTES"` | no |
| <a name="input_inspector2_resource_types"></a> [inspector2\_resource\_types](#input\_inspector2\_resource\_types) | Resource types Inspector v2 scans, both for this account and (auto-enable) for every organization member. | `list(string)` | <pre>[<br/>  "EC2",<br/>  "ECR",<br/>  "LAMBDA"<br/>]</pre> | no |
| <a name="input_is_primary_region"></a> [is\_primary\_region](#input\_is\_primary\_region) | Whether this call is the primary region. GuardDuty, Security Hub, Inspector v2 and Macie are regional<br/>services, so this module is meant to be applied in every allowed region; each region gets its own detector /<br/>account-enablement / org auto-enable configuration. A few resources are NOT regional in effect (the Security<br/>Hub cross-region finding aggregator, and Detective, which this module only stands up once) and are created<br/>only when this is true. | `bool` | `true` | no |
| <a name="input_macie_finding_publishing_frequency"></a> [macie\_finding\_publishing\_frequency](#input\_macie\_finding\_publishing\_frequency) | How often Macie exports findings to CloudWatch Events / EventBridge. | `string` | `"FIFTEEN_MINUTES"` | no |
| <a name="input_securityhub_auto_enable_controls"></a> [securityhub\_auto\_enable\_controls](#input\_securityhub\_auto\_enable\_controls) | Whether new controls added to a subscribed standard are enabled automatically. | `bool` | `true` | no |
| <a name="input_securityhub_standards"></a> [securityhub\_standards](#input\_securityhub\_standards) | Security Hub standards to subscribe to, by short name. | `list(string)` | <pre>[<br/>  "fsbp",<br/>  "cis-v3"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_detective_graph_arn"></a> [detective\_graph\_arn](#output\_detective\_graph\_arn) | ARN of the Detective behavior graph, or null when enable\_detective (or is\_primary\_region) is false |
| <a name="output_finding_aggregator_arn"></a> [finding\_aggregator\_arn](#output\_finding\_aggregator\_arn) | ARN of the Security Hub cross-region finding aggregator, or null outside the primary region |
| <a name="output_guardduty_detector_id"></a> [guardduty\_detector\_id](#output\_guardduty\_detector\_id) | ID of this account's GuardDuty detector |
| <a name="output_inspector2_enabler_id"></a> [inspector2\_enabler\_id](#output\_inspector2\_enabler\_id) | ID of the Inspector v2 enabler resource for this account |
| <a name="output_macie_account_id"></a> [macie\_account\_id](#output\_macie\_account\_id) | ID of the Macie account resource, or null when enable\_macie is false |
| <a name="output_securityhub_account_id"></a> [securityhub\_account\_id](#output\_securityhub\_account\_id) | ID of the Security Hub account resource (this account's Security Hub subscription) |
<!-- END_TF_DOCS -->
