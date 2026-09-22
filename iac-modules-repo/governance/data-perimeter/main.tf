# Resource Control Policies for a data perimeter (PLAN 4.6): deny access to S3, KMS, SQS, Secrets Manager (and,
# opt-in, STS) from any principal outside this organization, and require TLS. Applied from the management
# account, like SCPs. RCPs also close the PLAN 3.7 gap where a queue or topic policy set through
# sqs:SetQueueAttributes / sns:SetTopicAttributes could still grant access to an outside principal: RCPs act on
# the RESOURCE side, so a permissive queue policy no longer matters for the accounts this is attached to. SNS
# is not covered here: at the time this module was written, RCPs do not support SNS (check the current AWS
# documentation); the PLAN 3.7 second follow-up (an SCP or Config rule for SNS) is still open.

locals {
  tags = merge({ Service = "governance-data-perimeter", ManagedBy = "Terragrunt-Wrapper" }, var.tags)

  # Action namespace per service, used as-is (Action = "<service>:*") for every service except sts.
  service_action_namespace = {
    s3             = "s3:*"
    kms            = "kms:*"
    sqs            = "sqs:*"
    secretsmanager = "secretsmanager:*"
  }

  # sts cannot use the "sts:*" wildcard: a statement may carry Action or NotAction, never both, and the
  # exemption (var.sts_federation_exempt_actions) has to come out of the SAME Action list, not a separate
  # NotAction (NotAction with no Action would match every OTHER service's actions too, not just STS's). So
  # this is an explicit list of STS actions (current as of when this module was written; check the current
  # AWS documentation before relying on it) minus the exempted ones.
  all_sts_actions = [
    "sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity", "sts:AssumeRoot",
    "sts:DecodeAuthorizationMessage", "sts:GetAccessKeyInfo", "sts:GetCallerIdentity", "sts:GetFederationToken",
    "sts:GetServiceBearerToken", "sts:GetSessionToken", "sts:SetContext", "sts:SetSourceIdentity", "sts:TagSession",
  ]
  sts_actions_to_deny = setsubtract(local.all_sts_actions, var.sts_federation_exempt_actions)

  org_identity_statements = {
    for service in var.enabled_services : service => {
      Sid       = "EnforceOrgIdentities"
      Effect    = "Deny"
      Principal = "*"
      # A wildcard string for every service except sts, a list for sts (see all_sts_actions above): routed
      # through jsonencode/jsondecode so the two branches don't need one unified Terraform type.
      Action   = jsondecode(service == "sts" ? jsonencode(tolist(local.sts_actions_to_deny)) : jsonencode(local.service_action_namespace[service]))
      Resource = "*"
      Condition = {
        StringNotEqualsIfExists = { "aws:PrincipalOrgID" = var.organization_id }
        BoolIfExists            = { "aws:PrincipalIsAWSService" = "false" }
      }
    }
  }

  rcp_documents = {
    for service in var.enabled_services : service => jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.org_identity_statements[service],
        {
          Sid       = "EnforceTLS"
          Effect    = "Deny"
          Principal = "*"
          Action    = local.org_identity_statements[service].Action # same action list as the statement above
          Resource  = "*"
          Condition = { BoolIfExists = { "aws:SecureTransport" = "false" } }
        },
      ]
    })
  }
}

resource "aws_organizations_policy" "data_perimeter" {
  for_each = local.rcp_documents

  name        = "data-perimeter-${each.key}"
  description = "Data perimeter for ${each.key}: deny access from outside the organization, and require TLS."
  type        = "RESOURCE_CONTROL_POLICY"
  content     = each.value

  tags = local.tags
}

resource "aws_organizations_policy_attachment" "data_perimeter" {
  for_each = {
    for pair in setproduct(keys(local.rcp_documents), var.target_ous) :
    "${pair[0]}/${pair[1]}" => { service = pair[0], ou = pair[1] }
  }

  policy_id = aws_organizations_policy.data_perimeter[each.value.service].id
  target_id = var.target_ou_ids[each.value.ou]
}
