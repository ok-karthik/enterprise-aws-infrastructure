# network/central-endpoints

Shared VPC interface endpoints (PLAN 5.4), applied once in a **shared-services** account: one interface endpoint per service in `var.services` (ECR api/dkr, STS, SSM, SSM Messages, EC2 Messages, CloudWatch Logs, KMS, Secrets Manager, EKS), and one **private hosted zone per service**, so every spoke VPC that associates with these zones resolves the same shared endpoint — instead of every VPC paying for (and managing) its own copy.

**Gateway endpoints (S3, DynamoDB) are not here.** They're free, and stay local to each VPC.

## Why a private hosted zone, not the endpoint's own private DNS

An interface endpoint's own `private_dns_enabled` only resolves inside its own VPC. To share ONE endpoint across many VPCs, this module turns that off (`private_dns_enabled = false`) and instead creates its own Route 53 **private hosted zone** per service, with an alias record to the endpoint. A spoke VPC resolves the endpoint centrally once its zone association is set up (see below) — the standard AWS pattern for centralizing PrivateLink endpoints.

## Sharing a zone with a spoke (cross-account)

Every real spoke VPC is in a **different** account, so sharing a zone is two steps:
1. **Here** (this module, given `var.spoke_vpcs`): `aws_route53_vpc_association_authorization`, one per service per spoke — the authorization side.
2. **In the spoke's own account** (not built by this module): `aws_route53_zone_association`, using `hosted_zone_ids` from this module's output. A candidate for a small addition to `network/vpc` or a workload-account-side module later.

## Not verified offline

- The private DNS zone names (`api.ecr.<region>.amazonaws.com`, etc.) and that the endpoint's `dns_entry[0]` really is the regional (non-AZ-specific) entry — both checked against the provider schema and general AWS PrivateLink documentation, neither against a real deployment.
- The full cross-account association flow, end to end.

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
| [aws_cloudwatch_log_group.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_vpc_association_authorization.spokes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_vpc_association_authorization) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | CIDR blocks allowed to reach the endpoints on 443 (normally the platform's whole IPAM address space, so every spoke VPC is covered without listing each one). | `list(string)` | n/a | yes |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability zones to spread the interface endpoints across. | `list(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for every resource. | `string` | `"central-endpoints"` | no |
| <a name="input_services"></a> [services](#input\_services) | Short service names to create an interface endpoint (and a matching shareable private hosted zone) for.<br/>"ecr\_api" and "ecr\_dkr" are ECR's two distinct endpoints; the rest are the AWS service name as used in<br/>com.amazonaws.<region>.<service>. | `list(string)` | <pre>[<br/>  "ecr_api",<br/>  "ecr_dkr",<br/>  "sts",<br/>  "ssm",<br/>  "ssmmessages",<br/>  "ec2messages",<br/>  "logs",<br/>  "kms",<br/>  "secretsmanager",<br/>  "eks"<br/>]</pre> | no |
| <a name="input_spoke_vpcs"></a> [spoke\_vpcs](#input\_spoke\_vpcs) | Spoke VPCs to share every service's private hosted zone with, so they resolve the endpoints centrally.<br/>Every real spoke is in a DIFFERENT account, so this only creates the authorization side<br/>(aws\_route53\_vpc\_association\_authorization) here; the spoke account must create its own<br/>aws\_route53\_zone\_association for each zone (not built by this module -- see the README). | <pre>list(object({<br/>    vpc_id     = string<br/>    vpc_region = string<br/>  }))</pre> | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR for the shared-endpoints VPC. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_endpoint_ids"></a> [endpoint\_ids](#output\_endpoint\_ids) | Service short name => interface endpoint ID |
| <a name="output_hosted_zone_ids"></a> [hosted\_zone\_ids](#output\_hosted\_zone\_ids) | Service short name => private hosted zone ID (share this with a spoke account for its own aws\_route53\_zone\_association) |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the shared-endpoints VPC |
<!-- END_TF_DOCS -->
