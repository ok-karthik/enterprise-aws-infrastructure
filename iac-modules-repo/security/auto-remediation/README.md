# security/auto-remediation

A Lambda (PLAN 4.9) that removes open SSH/RDP security group rules automatically. Applied in **security-tooling**.

## What it reacts to, and what it does not (yet)

**Built:** an EventBridge rule matching the CloudTrail `AuthorizeSecurityGroupIngress` event. **Not built:** the second trigger PLAN 4.9 asks for — the matching AWS Config rule (`restricted-ssh` / `vpc-sg-open-only-to-authorized-ports`). PLAN 4.3 (the org Config recorder and conformance packs) is out of scope for the PR this module was written in, so there is no Config rule to react to yet. Add it the same way once 4.3 exists: a second rule on the central bus below, for the Config compliance-change event, forwarded from each member account the same way.

## Cross-account event delivery

EventBridge only sees events for API activity made in its **own** account — even for an organization CloudTrail (`security/org-cloudtrail` already covers the audit trail itself; this is a separate, well-known EventBridge limitation). A member account's `AuthorizeSecurityGroupIngress` event cannot be matched by a rule on security-tooling's default bus directly.

The fix, and what this module builds:
1. A **custom event bus** here (`auto-remediation`), with a resource policy that lets any account in the organization `PutEvents` on it.
2. A small EventBridge rule **in each member account** (added by `governance/account-baseline`, not by this module) that forwards the same `AuthorizeSecurityGroupIngress` event to this bus.
3. A rule on **this** bus, matching the forwarded event, targeting the Lambda.

## What the Lambda does

1. Assumes the `security-remediation` role (`var.remediation_role_name`) in the account the event came from (that role is created by `governance/account-baseline`, only when it is given this Lambda's role ARN).
2. Describes the security group named in the event and finds every ingress rule that opens port 22 or 3389 to `0.0.0.0/0` or `::/0` (`find_open_management_port_rules`, pure and unit-tested, `src/remediate_open_ssh.py`).
3. Revokes those rules and tags the group `remediated-by=auto`.
4. Publishes a summary (which group, which account, how many rules, how long it took) to `var.alert_topic_arn` (`security/security-alerts`'s topic).

## Testing

- **Python** (`tests/test_remediate_open_ssh.py`, `python3 -m unittest discover`): the AWS-facing functions take a client as an argument, so the tests pass in hand-written fake clients — no `moto`, no `boto3` install needed to run them (both were acceptable per PLAN 4.9; this repo's environment did not have either installed, and installing them would have cost mobile data). `boto3` itself is imported lazily inside `handler()` for the same reason: importing this module for its pure, unit-tested functions never requires `boto3`.
- **mypy**: not run. It is not installed in the environment this module was written in. The code carries full type hints and passes `python3 -m py_compile`; run `mypy src/` before the first real deploy.
- **Terraform** (`tests/*.tftest.hcl`): the event bus policy, the rule, the Lambda's IAM policy and its environment variables.

## Measuring it: `docs/runbooks/auto-remediation.md`

The target is under 30 seconds from the rule being created to its removal. **Not measured yet**: that needs a real deployment (an actual `AuthorizeSecurityGroupIngress` call, a real Lambda invocation). The runbook has the steps and a place to record the number once it is run for real.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.4 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_event_bus.central](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus) | resource |
| [aws_cloudwatch_event_bus_policy.central](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_bus_policy) | resource |
| [aws_cloudwatch_event_rule.authorize_security_group_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.remediate_open_ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [archive_file.lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alert_topic_arn"></a> [alert\_topic\_arn](#input\_alert\_topic\_arn) | ARN of the security/security-alerts SNS topic (that module's output topic\_arn, applied in this same account) to publish remediation summaries to. | `string` | n/a | yes |
| <a name="input_lambda_timeout_seconds"></a> [lambda\_timeout\_seconds](#input\_lambda\_timeout\_seconds) | Lambda timeout. Kept short: the whole point is remediating in well under 30 seconds (docs/runbooks/auto-remediation.md). | `number` | `30` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention for the Lambda's log group. | `number` | `90` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | ID of the AWS Organization (o-xxxxxxxxxx). The central event bus only accepts PutEvents from principals in this org. | `string` | n/a | yes |
| <a name="input_remediation_role_name"></a> [remediation\_role\_name](#input\_remediation\_role\_name) | Name of the role the Lambda assumes in the member account (governance/account-baseline creates it). Must match that module's role name exactly. | `string` | `"security-remediation"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_event_bus_arn"></a> [event\_bus\_arn](#output\_event\_bus\_arn) | ARN of the central event bus that member accounts forward AuthorizeSecurityGroupIngress events to |
| <a name="output_event_bus_name"></a> [event\_bus\_name](#output\_event\_bus\_name) | Name of the central event bus (member-account forwarding rules, added by governance/account-baseline, target this by name) |
| <a name="output_lambda_function_arn"></a> [lambda\_function\_arn](#output\_lambda\_function\_arn) | ARN of the auto-remediation Lambda |
<!-- END_TF_DOCS -->
