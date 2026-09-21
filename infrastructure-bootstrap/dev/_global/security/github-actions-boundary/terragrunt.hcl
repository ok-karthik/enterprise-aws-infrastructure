# Permissions boundary for the github-actions-apply role.
#
# The apply role still carries AdministratorAccess (PLAN 3.4 narrows that), but a boundary caps
# what it can actually do: even an admin policy cannot reach the organization, Identity Center,
# CloudTrail, or the CI identity (this boundary, the github-actions-* roles, the OIDC provider).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr://registry.terraform.io/terraform-aws-modules/iam/aws//modules/iam-policy?version=6.6.0"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_id   = local.account_vars.locals.aws_account_id

  boundary_name = "github-actions-apply-boundary"
}

inputs = {
  name        = local.boundary_name
  description = "Permissions boundary for github-actions-apply: blocks org, Identity Center, CloudTrail and CI-identity changes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEverythingElse"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        Sid    = "DenyOrganizationAndIdentityCenter"
        Effect = "Deny"
        Action = [
          "organizations:*",
          "account:*",
          "sso:*",
          "sso-directory:*",
          "identitystore:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyCloudTrailChanges"
        Effect = "Deny"
        Action = [
          "cloudtrail:Create*",
          "cloudtrail:Delete*",
          "cloudtrail:Update*",
          "cloudtrail:Put*",
          "cloudtrail:Stop*",
          "cloudtrail:RegisterOrganizationDelegatedAdmin",
          "cloudtrail:DeregisterOrganizationDelegatedAdmin"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyEditingThisBoundary"
        Effect = "Deny"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion"
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/${local.boundary_name}"
      },
      {
        Sid    = "DenyEditingCiRoles"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DeleteRole",
          "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePermissionsBoundary",
          "iam:PutRolePolicy",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateRole"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/github-actions-*"
      },
      {
        Sid    = "DenyEditingGithubOidcProvider"
        Effect = "Deny"
        Action = [
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint"
        ]
        Resource = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    ]
  })

  tags = {
    Role = "github-actions-boundary"
  }
}
