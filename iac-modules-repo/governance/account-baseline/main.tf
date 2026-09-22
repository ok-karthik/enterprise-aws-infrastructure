# Account baseline, applied to EVERY account (management, workloads, ...). The state bucket, the OIDC
# provider and the CI roles are NOT here: they come from the Day-0 bootstrap (CloudFormation / StackSets),
# because this module needs them before it can run.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  boundary_name = "platform-workload-boundary"
  boundary_arn  = "arn:${local.partition}:iam::${local.account_id}:policy/${local.boundary_name}"

  tags = merge(
    {
      Service   = "governance-account-baseline"
      ManagedBy = "Terragrunt-Wrapper"
    },
    var.tags
  )
}

# ------------------------------------------------------------------------------
# 1. Account alias and IAM password policy
# ------------------------------------------------------------------------------
resource "aws_iam_account_alias" "this" {
  count         = var.account_alias != "" ? 1 : 0
  account_alias = var.account_alias
}

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = var.password_policy_min_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
  hard_expiry                    = false
}

# ------------------------------------------------------------------------------
# 2. Account-wide safe defaults
# ------------------------------------------------------------------------------
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# IMDSv2 as the default for new instances in this region. The hop limit is left to each workload
# (EKS nodes set 1 in the eks module).
resource "aws_ec2_instance_metadata_defaults" "this" {
  http_tokens   = "required"
  http_endpoint = "enabled"
}

# ------------------------------------------------------------------------------
# 3. KMS keys per data class (rotation on)
# ------------------------------------------------------------------------------
locals {
  # Standard key policy: the account root delegates key use to IAM (the AWS default), so the key stays manageable.
  kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIamPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_kms_key" "general" {
  description             = "Platform key for general (internal) data in this account"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = local.kms_policy

  tags = merge(local.tags, { DataClass = "general" })
}

resource "aws_kms_alias" "general" {
  name          = "alias/platform-general"
  target_key_id = aws_kms_key.general.key_id
}

resource "aws_kms_key" "confidential" {
  description             = "Platform key for confidential data in this account"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = local.kms_policy

  tags = merge(local.tags, { DataClass = "confidential" })
}

resource "aws_kms_alias" "confidential" {
  name          = "alias/platform-confidential"
  target_key_id = aws_kms_key.confidential.key_id
}

# ------------------------------------------------------------------------------
# 4. platform-workload-boundary: every role that Terraform, ACK or tenants create must carry it
# ------------------------------------------------------------------------------
locals {
  # A permissions boundary must Allow everything and then Deny specific actions: it only ever narrows a role.
  workload_boundary_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEverythingElse"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      },
      {
        # A role created under this boundary can only create roles that carry the same boundary, so
        # the boundary cannot be shed by creating a new role.
        Sid       = "DenyRoleWithoutThisBoundary"
        Effect    = "Deny"
        Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource  = "*"
        Condition = { StringNotEquals = { "iam:PermissionsBoundary" = local.boundary_arn } }
      },
      {
        Sid      = "DenyBoundaryRemoval"
        Effect   = "Deny"
        Action   = ["iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary", "iam:PutUserPermissionsBoundary"]
        Resource = "*"
      },
      {
        Sid      = "DenyEditingThisBoundary"
        Effect   = "Deny"
        Action   = ["iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion"]
        Resource = local.boundary_arn
      },
      {
        Sid      = "DenyHumanIdentitiesAndKeys"
        Effect   = "Deny"
        Action   = ["iam:CreateUser", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "iam:CreateAccessKey"]
        Resource = "*"
      },
      {
        Sid    = "DenyEditingPlatformRoles"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateRole",
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/platform-*",
          "arn:${local.partition}:iam::${local.account_id}:role/terraform-*",
          "arn:${local.partition}:iam::${local.account_id}:role/github-actions-*",
          "arn:${local.partition}:iam::${local.account_id}:role/OrganizationAccountAccessRole",
        ]
      },
      {
        Sid    = "DenySecurityServiceTampering"
        Effect = "Deny"
        Action = [
          "access-analyzer:DeleteAnalyzer",
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder",
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:StopMonitoringMembers",
          "macie2:DisableMacie",
          "securityhub:BatchDisableStandards",
          "securityhub:DisableSecurityHub",
          "securityhub:DisassociateFromAdministratorAccount",
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyLoweringAccountDefaults"
        Effect = "Deny"
        Action = [
          "ec2:DisableEbsEncryptionByDefault",
          "ec2:ModifyInstanceMetadataDefaults",
          "iam:DeleteAccountPasswordPolicy",
          "iam:UpdateAccountPasswordPolicy",
          "s3:PutAccountPublicAccessBlock",
        ]
        Resource = "*"
      },
      {
        Sid      = "DenyOrganizationAndIdentity"
        Effect   = "Deny"
        Action   = ["account:*", "identitystore:*", "organizations:*", "sso-directory:*", "sso:*"]
        Resource = "*"
      },
    ]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  # A permissions boundary must Allow everything and then Deny specific actions: it grants nothing, it only ever
  # narrows the role it is attached to. Checkov flags the broad Allow (and reads no Deny), so these are expected.
  #checkov:skip=CKV_AWS_62: "Permissions boundary: Allow */* followed by explicit Denies. It caps roles, it does not grant access"
  #checkov:skip=CKV_AWS_63: "Permissions boundary: Action * is the base Allow that the Deny statements then narrow"
  #checkov:skip=CKV2_AWS_40: "Permissions boundary: a boundary cannot restrict IAM by allowing less, it denies specific IAM actions (DenyBoundaryRemoval, DenyEditingThisBoundary, DenyHumanIdentitiesAndKeys, DenyEditingPlatformRoles)"
  #checkov:skip=CKV_AWS_286: "Permissions boundary: privilege escalation is what the Deny statements remove (no new role without this boundary, no user or key creation, no editing of platform roles)"
  #checkov:skip=CKV_AWS_287: "Permissions boundary: credential creation is denied (DenyHumanIdentitiesAndKeys)"
  #checkov:skip=CKV_AWS_288: "Permissions boundary: it grants nothing; the effective permissions are the intersection with the role's own policies"
  #checkov:skip=CKV_AWS_289: "Permissions boundary: permissions management is narrowed by the Deny statements, not granted"
  #checkov:skip=CKV_AWS_290: "Permissions boundary: it grants nothing; write access comes from the role's own policy and is capped here"
  #checkov:skip=CKV_AWS_355: "Permissions boundary: Resource * on the base Allow is intended, the Denies name the resources they protect"
  name        = local.boundary_name
  description = "Permissions boundary for every role created by Terraform, ACK or tenants in this account"
  policy      = jsonencode(local.workload_boundary_policy)

  tags = local.tags
}

# ------------------------------------------------------------------------------
# 4b. platform-developer: the customer-managed policy behind the Developer permission set
# ------------------------------------------------------------------------------
# Identity Center attaches a customer-managed policy BY NAME, and the policy must exist in every
# account the permission set is assigned to, so it lives in the baseline. The Developer set also
# carries platform-workload-boundary, which caps it further. Developers are only assigned to
# NonProd / Sandbox accounts (read-only ReadOnly in Prod).
#
# ABAC: instances can only be started, stopped, rebooted or terminated by a principal whose `team`
# session tag (from the IdP, see identity-center) equals the instance's `team` tag, and new
# instances must be launched with the caller's own `team` tag.
locals {
  developer_policy_name = "platform-developer"

  # Instance resources of ssm:SendCommand and ssm:StartSession: EC2 instances and hybrid managed instances.
  ssm_instance_arns = [
    "arn:${local.partition}:ec2:*:${local.account_id}:instance/*",
    "arn:${local.partition}:ssm:*:${local.account_id}:managed-instance/*",
  ]

  developer_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowWorkloadServices"
        Effect = "Allow"
        Action = [
          "apigateway:*",
          "athena:*",
          "autoscaling:*",
          "cloudwatch:*",
          "dynamodb:*",
          "ecr:*",
          "ecs:*",
          "eks:*",
          "elasticloadbalancing:*",
          "events:*",
          "glue:*",
          "kinesis:*",
          "lambda:*",
          "logs:*",
          "rds:*",
          "s3:*",
          "sns:*",
          "sqs:*",
          "ssm:*",
          "states:*",
          "xray:*",
        ]
        Resource = "*"
      },
      {
        Sid      = "AllowReadOnlyElsewhere"
        Effect   = "Allow"
        Action   = ["cloudformation:Describe*", "cloudformation:Get*", "cloudformation:List*", "ec2:Describe*", "ec2:Get*", "route53:Get*", "route53:List*", "secretsmanager:Describe*", "secretsmanager:List*", "iam:Get*", "iam:List*"]
        Resource = "*"
      },
      {
        Sid       = "AllowPassingPlatformRoles"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:${local.partition}:iam::${local.account_id}:role/platform/*"
        Condition = { StringEquals = { "iam:PassedToService" = ["ecs-tasks.amazonaws.com", "eks.amazonaws.com", "lambda.amazonaws.com", "states.amazonaws.com"] } }
      },
      {
        Sid      = "AllowEncryptedDataViaServices"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*"]
        Resource = "*"
        Condition = {
          StringLike = { "kms:ViaService" = ["dynamodb.*.amazonaws.com", "logs.*.amazonaws.com", "rds.*.amazonaws.com", "s3.*.amazonaws.com", "secretsmanager.*.amazonaws.com", "sns.*.amazonaws.com", "sqs.*.amazonaws.com"] }
        }
      },
      {
        Sid      = "ControlOwnTeamInstances"
        Effect   = "Allow"
        Action   = ["ec2:RebootInstances", "ec2:StartInstances", "ec2:StopInstances", "ec2:TerminateInstances"]
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/team" = "$${aws:PrincipalTag/team}" }
        }
      },
      {
        Sid      = "LaunchInstancesTaggedForOwnTeam"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:instance/*"
        Condition = {
          StringEquals = { "aws:RequestTag/team" = "$${aws:PrincipalTag/team}" }
        }
      },
      {
        Sid    = "LaunchInstancesSupportingResources"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "arn:${local.partition}:ec2:*::image/*",
          "arn:${local.partition}:ec2:*:${local.account_id}:network-interface/*",
          "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*",
          "arn:${local.partition}:ec2:*:${local.account_id}:subnet/*",
          "arn:${local.partition}:ec2:*:${local.account_id}:volume/*",
        ]
      },
      {
        Sid       = "TagOnCreate"
        Effect    = "Allow"
        Action    = "ec2:CreateTags"
        Resource  = "arn:${local.partition}:ec2:*:${local.account_id}:*/*"
        Condition = { StringEquals = { "ec2:CreateAction" = ["RunInstances", "CreateVolume"] } }
      },

      # --- Explicit denies. The service-wide allows above (s3:*, sqs:*, ssm:*, ...) are what lets a developer
      # build and debug a workload; these carve out the ways to widen access to it or to change the platform.

      {
        # Resource policies are how data is exposed outside the account. A developer builds a workload; who
        # else may reach its bucket, queue, topic, function or repository is a platform decision. (The data
        # perimeter SCP/RCPs of PLAN 4.6 are the backstop.)
        Sid    = "DenyResourcePolicyWrites"
        Effect = "Deny"
        Action = [
          "ecr:SetRepositoryPolicy",
          "lambda:AddPermission",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutObjectAcl",
          "sns:AddPermission",
          "sqs:AddPermission",
        ]
        Resource = "*"
      },
      {
        # A Lambda function URL with AuthType NONE is a public endpoint. AWS_IAM URLs are allowed (callers must
        # sign requests), so this is a condition on the auth type and not an outright deny of function URLs.
        # UpdateFunctionUrlConfig is covered too, or a URL created as AWS_IAM could be switched to NONE.
        # When an update does not change the auth type the key is absent and the call is allowed: an existing
        # public URL is not fixed by this, it only cannot be created or switched to.
        Sid       = "DenyPublicLambdaFunctionUrls"
        Effect    = "Deny"
        Action    = ["lambda:CreateFunctionUrlConfig", "lambda:UpdateFunctionUrlConfig"]
        Resource  = "*"
        Condition = { StringEquals = { "lambda:FunctionUrlAuthType" = "NONE" } }
      },
      {
        # /platform/* is the discovery contract (docs/DISCOVERY_CONTRACT.md): tenants read it, only the
        # platform writes it. Reading stays allowed (ssm:* above).
        Sid    = "DenyPlatformParameterWrites"
        Effect = "Deny"
        Action = [
          "ssm:AddTagsToResource",
          "ssm:DeleteParameter",
          "ssm:DeleteParameters",
          "ssm:LabelParameterVersion",
          "ssm:PutParameter",
        ]
        Resource = "arn:${local.partition}:ssm:*:${local.account_id}:parameter/platform/*"
      },
      {
        # Running commands on, or opening a shell to, an instance is limited to the developer's own team
        # (ABAC on the team tag). Instances only: SSM documents are a different resource type and stay allowed.
        # An instance without a team tag is denied too (the tag is absent, so it cannot match).
        Sid      = "DenySsmAccessToOtherTeamsInstances"
        Effect   = "Deny"
        Action   = ["ssm:SendCommand", "ssm:StartSession"]
        Resource = local.ssm_instance_arns
        Condition = {
          StringNotEquals = { "aws:ResourceTag/team" = "$${aws:PrincipalTag/team}" }
        }
      },
      {
        # A principal with no team tag has nothing to compare, so it may not use SSM on instances at all.
        Sid       = "DenySsmAccessWithoutTeamTag"
        Effect    = "Deny"
        Action    = ["ssm:SendCommand", "ssm:StartSession"]
        Resource  = local.ssm_instance_arns
        Condition = { Null = { "aws:PrincipalTag/team" = "true" } }
      },
    ]
  }
}

resource "aws_iam_policy" "developer" {
  # Checkov's IAM checks read only the Allow statements and do not subtract the explicit Denies, so these stay
  # reported even though the policy carves out resource-policy writes, /platform/* parameter writes and
  # cross-team SSM access (statements DenyResourcePolicyWrites, DenyPlatformParameterWrites, DenySsm*).
  #checkov:skip=CKV_AWS_286: "iam:PassRole is limited to role/platform/* and only to compute services; the Developer set also carries platform-workload-boundary, which denies creating roles without it, editing platform roles and touching Organizations. Assigned only in NonProd/Sandbox (PLAN 3.2, enforced by identity-center)"
  #checkov:skip=CKV_AWS_287: "Reading secrets and parameters is the job in a NonProd/Sandbox account, which holds no production credentials; /platform/* parameters are non-sensitive discovery metadata. Access keys and login profiles are denied by platform-workload-boundary"
  #checkov:skip=CKV_AWS_288: "Developers work with workload data (S3, DynamoDB, RDS, ...) in NonProd/Sandbox accounts, so broad service actions are the point of the set. Exposure outside the organization is blocked by the explicit resource-policy Deny in this policy and by the SCP/RCP data perimeter (PLAN 4.6)"
  #checkov:skip=CKV_AWS_289: "The resource-policy and permission-granting actions (s3:PutBucketPolicy, sqs/sns/lambda AddPermission, ecr:SetRepositoryPolicy, ...) are explicitly denied by DenyResourcePolicyWrites in this same policy; Checkov does not evaluate Deny statements. The data perimeter (PLAN 4.6) is the backstop"
  #checkov:skip=CKV_AWS_290: "Writing to workload services is required to build and run a workload. The set is NonProd/Sandbox-only (PLAN 3.2), capped by platform-workload-boundary, and EC2 start/stop/terminate/launch and SSM access are scoped to the developer's own team by the team tag (ABAC)"
  #checkov:skip=CKV_AWS_355: "Developers create the resources, so their names and ARNs do not exist when the policy is written and cannot be listed. Scope comes from the account (NonProd/Sandbox only), the boundary, the region SCP and ABAC on the team tag, not from resource ARNs"
  name        = local.developer_policy_name
  description = "Customer-managed policy of the Developer permission set: workload services, ABAC on EC2 by the team tag"
  policy      = jsonencode(local.developer_policy)

  tags = local.tags
}

# ------------------------------------------------------------------------------
# 5. DISCOVERY CONTRACT (account dimension, PLAN 2.7): who and where this account is, and its keys
# ------------------------------------------------------------------------------
locals {
  discovery_parameters = var.publish_ssm_parameters ? {
    "account/id"                = local.account_id
    "account/ou"                = var.ou
    "kms/general_key_arn"       = aws_kms_key.general.arn
    "kms/confidential_key_arn"  = aws_kms_key.confidential.arn
    "iam/workload_boundary_arn" = aws_iam_policy.workload_boundary.arn
    "iam/developer_policy_arn"  = aws_iam_policy.developer.arn
  } : {}
}

# ------------------------------------------------------------------------------
# 6. security-remediation (PLAN 4.9): a narrow role the auto-remediation Lambda in security-tooling assumes
# to revoke open SSH/RDP security group rules in THIS account. Nothing here forwards the CloudTrail event
# that triggers it: iac-modules-repo/security/auto-remediation's README explains why that has to be a
# separate EventBridge rule (not built by this module) on this account's own default event bus.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "security_remediation" {
  count = var.security_remediation_lambda_role_arn != "" ? 1 : 0

  name = "security-remediation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAutoRemediationLambda"
      Effect    = "Allow"
      Principal = { AWS = var.security_remediation_lambda_role_arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "security_remediation" {
  count = var.security_remediation_lambda_role_arn != "" ? 1 : 0

  name = "revoke-open-management-ports"
  role = aws_iam_role.security_remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # DescribeSecurityGroups has no resource-level permissions: AWS requires Resource = "*" for it.
        Sid      = "DescribeSecurityGroups"
        Effect   = "Allow"
        Action   = "ec2:DescribeSecurityGroups"
        Resource = "*"
      },
      {
        Sid      = "RevokeOpenIngress"
        Effect   = "Allow"
        Action   = "ec2:RevokeSecurityGroupIngress"
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*"
      },
      {
        # Can only ever set the one tag key the Lambda uses to mark what it touched.
        Sid       = "TagRemediatedGroups"
        Effect    = "Allow"
        Action    = "ec2:CreateTags"
        Resource  = "arn:${local.partition}:ec2:*:${local.account_id}:security-group/*"
        Condition = { "ForAllValues:StringEquals" = { "aws:TagKeys" = ["remediated-by"] } }
      },
    ]
  })
}

resource "aws_ssm_parameter" "discovery" {
  #checkov:skip=CKV2_AWS_34: "Platform discovery catalog parameter contains non-sensitive metadata"
  for_each = local.discovery_parameters

  name        = "/platform/${var.env}/${var.region}/${each.key}"
  description = "Platform Discovery Contract: ${each.key} for ${var.env} in ${var.region}"
  type        = "String"
  value       = each.value

  tags = local.tags
}
