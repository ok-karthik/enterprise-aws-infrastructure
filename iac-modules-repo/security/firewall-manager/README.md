# security/firewall-manager

AWS Firewall Manager (FMS) module for organization-wide edge and network security
(PLAN 6.1). Applied in the **security-tooling** account — the delegated FMS
administrator.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_fms_admin_account` | Registers this account as the FMS administrator |
| `aws_fms_policy.waf` | WAFv2 policy: AWS Managed Rule Groups applied to ALBs, API Gateways and CloudFront across target OUs |
| `aws_wafv2_rule_group.rate_limit` | Rate-based rule group (block after N requests / 5 min / IP) |
| `aws_fms_policy.sg_audit` | Security-group content audit: flags SGs with unrestricted ingress |
| `aws_fms_policy.network_firewall` | *(Optional)* Network Firewall policy when Phase 5.3 inspection-egress is deployed |

### WAFv2 managed rule groups (priority order)

1. **AWSManagedRulesCommonRuleSet** — OWASP Top 10, common exploits
2. **AWSManagedRulesKnownBadInputsRuleSet** — Log4Shell, Spring4Shell, bad bots
3. **AWSManagedRulesAmazonIpReputationList** — IPs flagged by AWS threat intelligence
4. **AWSManagedRulesAnonymousIpList** — VPN, proxy, Tor exit nodes
5. **AWSManagedRulesBotControlRuleSet** *(optional, `enable_bot_control`)* — bot
   categorisation and mitigation. Start in COUNT mode (`bot_control_action = "COUNT"`)
   and review CloudWatch metrics before switching to BLOCK.

A **rate-based rule** (default 2 000 requests / 5 min / IP) is appended as the last
rule. Set `rate_limit = 0` to disable it.

## Prerequisites

1. The security-tooling account exists (account factory / registry).
2. `governance/organization` registers it as delegated administrator:
   ```hcl
   delegated_administrators = {
     "fms.amazonaws.com" = "<security-tooling account id>"
   }
   ```
3. `fms.amazonaws.com` is in `aws_service_access_principals`.

## Usage

```hcl
module "firewall_manager" {
  source = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/firewall-manager?ref=firewall-manager-v1.0.0"

  admin_account_id  = "222222222222"
  waf_target_ou_ids = ["ou-xxxx-workloads"]

  # Start in audit mode
  remediation_enabled = false

  # Bot Control for prod (COUNT first)
  enable_bot_control = true
  bot_control_action = "COUNT"

  tags = {
    Environment = "Global"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `admin_account_id` | 12-digit FMS admin account (security-tooling) | `string` | — | yes |
| `waf_target_ou_ids` | OU IDs for the WAFv2 policy | `list(string)` | — | yes |
| `waf_policy_name` | Name of the WAFv2 policy | `string` | `"platform-waf-policy"` | no |
| `waf_resource_types` | Resource types protected | `list(string)` | ALB, APIGW, CloudFront | no |
| `waf_default_action` | Default web ACL action | `string` | `"ALLOW"` | no |
| `rate_limit` | Requests/5min/IP, 0 = disabled | `number` | `2000` | no |
| `enable_bot_control` | Enable Bot Control rule group | `bool` | `false` | no |
| `bot_control_action` | Bot Control override: COUNT or BLOCK | `string` | `"COUNT"` | no |
| `per_ou_waf_overrides` | Per-OU rule group action overrides | `map(map(string))` | `{}` | no |
| `enable_sg_audit` | Enable SG content audit policy | `bool` | `true` | no |
| `sg_audit_policy_name` | Name of the SG audit policy | `string` | `"platform-sg-audit-policy"` | no |
| `sg_audit_target_ou_ids` | OU IDs for SG audit (defaults to WAF OUs) | `list(string)` | `[]` | no |
| `enable_network_firewall_policy` | Enable FMS Network Firewall policy | `bool` | `false` | no |
| `nfw_policy_name` | Name of the NFW policy | `string` | `"platform-network-firewall-policy"` | no |
| `nfw_target_ou_ids` | OU IDs for NFW policy | `list(string)` | `[]` | no |
| `nfw_stateful_rule_group_arns` | Stateful rule group ARNs | `list(string)` | `[]` | no |
| `exclude_account_ids` | Accounts excluded from all policies | `list(string)` | `[]` | no |
| `remediation_enabled` | Auto-remediate non-compliant resources | `bool` | `false` | no |
| `tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `waf_policy_id` | ID of the FMS WAFv2 policy |
| `waf_policy_arn` | Policy update token of the WAFv2 policy |
| `rate_limit_rule_group_arn` | ARN of the rate-based rule group |
| `sg_audit_policy_id` | ID of the SG audit policy |
| `network_firewall_policy_id` | ID of the NFW policy |

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
| [aws_fms_admin_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fms_admin_account) | resource |
| [aws_fms_policy.network_firewall](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fms_policy) | resource |
| [aws_fms_policy.sg_audit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fms_policy) | resource |
| [aws_fms_policy.waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fms_policy) | resource |
| [aws_wafv2_rule_group.rate_limit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_rule_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_account_id"></a> [admin\_account\_id](#input\_admin\_account\_id) | 12-digit ID of the FMS administrator (security-tooling). Delegation itself is done by governance/organization (delegated\_administrators["fms.amazonaws.com"]). | `string` | n/a | yes |
| <a name="input_bot_control_action"></a> [bot\_control\_action](#input\_bot\_control\_action) | Override action for Bot Control rules: COUNT (observe first) or BLOCK. Only used when enable\_bot\_control is true. | `string` | `"COUNT"` | no |
| <a name="input_enable_bot_control"></a> [enable\_bot\_control](#input\_enable\_bot\_control) | Enable the AWS Managed Bot Control rule group. Recommended for prod (count mode by default). | `bool` | `false` | no |
| <a name="input_enable_network_firewall_policy"></a> [enable\_network\_firewall\_policy](#input\_enable\_network\_firewall\_policy) | Enable the FMS Network Firewall policy. Only set this to true when Phase 5.3 (inspection-egress) is deployed. | `bool` | `false` | no |
| <a name="input_enable_sg_audit"></a> [enable\_sg\_audit](#input\_enable\_sg\_audit) | Enable the FMS security-group audit policy that flags overly open SGs. | `bool` | `true` | no |
| <a name="input_exclude_account_ids"></a> [exclude\_account\_ids](#input\_exclude\_account\_ids) | Account IDs to exclude from all FMS policies (management account, sandbox accounts, etc.). | `list(string)` | `[]` | no |
| <a name="input_nfw_policy_name"></a> [nfw\_policy\_name](#input\_nfw\_policy\_name) | Name of the FMS Network Firewall policy. | `string` | `"platform-network-firewall-policy"` | no |
| <a name="input_nfw_stateful_rule_group_arns"></a> [nfw\_stateful\_rule\_group\_arns](#input\_nfw\_stateful\_rule\_group\_arns) | ARNs of Network Firewall stateful rule groups to reference in the FMS policy. | `list(string)` | `[]` | no |
| <a name="input_nfw_target_ou_ids"></a> [nfw\_target\_ou\_ids](#input\_nfw\_target\_ou\_ids) | OU IDs that receive the Network Firewall policy. | `list(string)` | `[]` | no |
| <a name="input_rate_limit"></a> [rate\_limit](#input\_rate\_limit) | Requests per 5 minutes per IP before the rate-based rule blocks. 0 disables the rate-based rule. | `number` | `2000` | no |
| <a name="input_remediation_enabled"></a> [remediation\_enabled](#input\_remediation\_enabled) | Whether FMS auto-remediates non-compliant resources. Start with false (audit mode), then enable after reviewing findings. | `bool` | `false` | no |
| <a name="input_sg_audit_policy_name"></a> [sg\_audit\_policy\_name](#input\_sg\_audit\_policy\_name) | Name of the security-group audit policy. | `string` | `"platform-sg-audit-policy"` | no |
| <a name="input_sg_audit_target_ou_ids"></a> [sg\_audit\_target\_ou\_ids](#input\_sg\_audit\_target\_ou\_ids) | OU IDs audited by the SG policy. Defaults to the same as waf\_target\_ou\_ids if empty. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_waf_default_action"></a> [waf\_default\_action](#input\_waf\_default\_action) | Default action for the managed web ACL. ALLOW lets through traffic that matches no rule; COUNT logs everything without blocking. | `string` | `"ALLOW"` | no |
| <a name="input_waf_policy_name"></a> [waf\_policy\_name](#input\_waf\_policy\_name) | Name of the FMS WAFv2 security policy. | `string` | `"platform-waf-policy"` | no |
| <a name="input_waf_resource_types"></a> [waf\_resource\_types](#input\_waf\_resource\_types) | Resource types protected by the WAFv2 policy. | `list(string)` | <pre>[<br/>  "AWS::ElasticLoadBalancingV2::LoadBalancer",<br/>  "AWS::ApiGateway::Stage",<br/>  "AWS::CloudFront::Distribution"<br/>]</pre> | no |
| <a name="input_waf_target_ou_ids"></a> [waf\_target\_ou\_ids](#input\_waf\_target\_ou\_ids) | OU IDs whose accounts receive the WAFv2 policy. Use the Workloads OU (or both Workloads + Infrastructure). | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_network_firewall_policy_id"></a> [network\_firewall\_policy\_id](#output\_network\_firewall\_policy\_id) | ID of the FMS Network Firewall policy (empty when disabled) |
| <a name="output_rate_limit_rule_group_arn"></a> [rate\_limit\_rule\_group\_arn](#output\_rate\_limit\_rule\_group\_arn) | ARN of the rate-based WAFv2 rule group (empty when rate\_limit is 0) |
| <a name="output_sg_audit_policy_id"></a> [sg\_audit\_policy\_id](#output\_sg\_audit\_policy\_id) | ID of the FMS security-group audit policy (empty when disabled) |
| <a name="output_waf_policy_arn"></a> [waf\_policy\_arn](#output\_waf\_policy\_arn) | ARN of the FMS WAFv2 security policy |
| <a name="output_waf_policy_id"></a> [waf\_policy\_id](#output\_waf\_policy\_id) | ID of the FMS WAFv2 security policy |
<!-- END_TF_DOCS -->
