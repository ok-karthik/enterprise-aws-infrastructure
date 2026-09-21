# Publishes the discovery contract (SSM Parameter Store) into ONE account, with the same parameter names
# in every workload account, so tenant Terraform reads /platform/<env>/<region>/... from its own account
# whatever account the underlying resource lives in (for example a VPC shared from a network hub).
# Values come from the outputs of the stacks that own them; this module only writes them.

resource "aws_ssm_parameter" "this" {
  #checkov:skip=CKV2_AWS_34: "Platform discovery catalog parameter contains non-sensitive metadata"
  for_each = var.parameters

  name        = "/platform/${var.env}/${var.region}/${each.key}"
  description = "Platform Discovery Contract: ${each.key} for ${var.env} in ${var.region}"
  type        = "String"
  value       = each.value

  tags = merge(
    {
      Service   = "governance-discovery-publisher"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}
