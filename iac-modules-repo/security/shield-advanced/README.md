# security/shield-advanced

**Status:** 📐 Design-only (tested offline; not wired into a live stack — ,000/mo Shield Advanced cost barrier)

AWS Shield Advanced module (PLAN 6.4): optional DDoS protection for production
resources. Disabled by default (`enabled = false`).

> ⚠️ **COST WARNING**: Shield Advanced costs **$3,000/month** per AWS Organization
> (not per account). The subscription covers all accounts once enabled in any one.
> Only enable when the business case justifies it. See `docs/FINOPS.md`.

## What it creates (when enabled)

| Resource | Purpose |
|---|---|
| `aws_shield_subscription` | Shield Advanced subscription (auto-renew) |
| `aws_shield_protection` | Per-resource protection (CloudFront, ALB, EIP, Route 53, GA) |
| `aws_shield_proactive_engagement` | Proactive engagement contacts for the SRT |
| `aws_shield_drt_access_role_arn_association` | DRT access to WAF resources |
| `aws_shield_application_layer_automatic_response` | Automatic WAF rate-based rules during DDoS |

## Usage

```hcl
module "shield" {
  source = "git::https://github.com/ok-karthik/enterprise-aws-infrastructure.git//iac-modules-repo/security/shield-advanced?ref=shield-advanced-v1.0.0"

  enabled = true

  protected_resources = {
    "prod-cloudfront" = "arn:aws:cloudfront::111111111111:distribution/EXXXXXXXXXX"
    "prod-alb"        = "arn:aws:elasticloadbalancing:eu-central-1:111111111111:loadbalancer/app/prod/abc"
  }

  enable_proactive_engagement = true
  proactive_engagement_contacts = [
    {
      email_address = "security@example.com"
      phone_number  = "+15555555555"
      note          = "Primary on-call"
    }
  ]

  auto_remediation_action = "COUNT" # observe first, then switch to BLOCK

  tags = { Environment = "Prod" }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `enabled` | Enable Shield Advanced subscription | `bool` | `false` | no |
| `protected_resources` | Name → ARN map of resources to protect | `map(string)` | `{}` | no |
| `enable_proactive_engagement` | Enable SRT proactive engagement | `bool` | `false` | no |
| `proactive_engagement_contacts` | SRT emergency contacts | `list(object)` | `[]` | no |
| `enable_auto_remediation` | Auto application-layer mitigation | `bool` | `true` | no |
| `auto_remediation_action` | COUNT or BLOCK | `string` | `"COUNT"` | no |
| `drt_access_role_arn` | IAM role for DRT access | `string` | `""` | no |
| `tags` | Tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `subscription_state` | ACTIVE or empty |
| `protection_ids` | Name → protection ID |
| `protection_arns` | Name → protection ARN |

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
| [aws_shield_application_layer_automatic_response.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/shield_application_layer_automatic_response) | resource |
| [aws_shield_drt_access_role_arn_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/shield_drt_access_role_arn_association) | resource |
| [aws_shield_proactive_engagement.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/shield_proactive_engagement) | resource |
| [aws_shield_protection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/shield_protection) | resource |
| [aws_shield_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/shield_subscription) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_auto_remediation_action"></a> [auto\_remediation\_action](#input\_auto\_remediation\_action) | Action for auto-remediation: COUNT (observe) or BLOCK. | `string` | `"COUNT"` | no |
| <a name="input_drt_access_role_arn"></a> [drt\_access\_role\_arn](#input\_drt\_access\_role\_arn) | ARN of the IAM role that grants the Shield Response Team access to your WAF resources. Empty = no DRT access. | `string` | `""` | no |
| <a name="input_enable_auto_remediation"></a> [enable\_auto\_remediation](#input\_enable\_auto\_remediation) | Enable automatic application-layer DDoS mitigation (WAF rate-based rules created by Shield). | `bool` | `true` | no |
| <a name="input_enable_proactive_engagement"></a> [enable\_proactive\_engagement](#input\_enable\_proactive\_engagement) | Enable proactive engagement with the AWS Shield Response Team during DDoS events. | `bool` | `false` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Enable Shield Advanced subscription. This costs $3,000/month per organization (not per account).<br/>Set to true ONLY for prod OU after reviewing the cost impact in docs/FINOPS.md. | `bool` | `false` | no |
| <a name="input_proactive_engagement_contacts"></a> [proactive\_engagement\_contacts](#input\_proactive\_engagement\_contacts) | Contacts for Shield Response Team (SRT) proactive engagement during DDoS events.<br/>Each entry must have email\_address, phone\_number and an optional note. | <pre>list(object({<br/>    email_address = string<br/>    phone_number  = string<br/>    note          = optional(string, "")<br/>  }))</pre> | `[]` | no |
| <a name="input_protected_resources"></a> [protected\_resources](#input\_protected\_resources) | Map of resource ARNs to protect with Shield Advanced. Each key is a friendly name, each value<br/>is the ARN. Supports CloudFront distributions, ALBs, EIPs, Route 53 hosted zones and<br/>Global Accelerators. | `map(string)` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_protection_arns"></a> [protection\_arns](#output\_protection\_arns) | Map of protection name => Shield protection ARN |
| <a name="output_protection_ids"></a> [protection\_ids](#output\_protection\_ids) | Map of protection name => Shield protection ID |
| <a name="output_subscription_state"></a> [subscription\_state](#output\_subscription\_state) | State of the Shield Advanced subscription (ACTIVE or empty if disabled) |
<!-- END_TF_DOCS -->
