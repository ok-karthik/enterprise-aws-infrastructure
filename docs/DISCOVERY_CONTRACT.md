# Discovery Contract (Platform Service Catalog)

Tenant Terraform, CDK, Pulumi, and the Internal Developer Platform (IDP) never hardcode AWS resource identifiers (VPC IDs, subnets, OIDC ARNs, cluster endpoints, CA data, key ARNs). Instead, infrastructure stacks publish their standard outputs into AWS Systems Manager (SSM) Parameter Store **in the target workload account** at plan/apply time.

---

## 1. Parameters Specification

All parameters are published under `/platform/<env>/<region>/`. `<env>` is `dev`, `staging`, `prod` or `global`, and `<region>` is the AWS region (e.g. `eu-central-1`).

| Key | Value Description | Type | Owner Module | What Breaks If Missing |
|---|---|---|---|---|
| `vpc/id` | The VPC ID | String | `governance/discovery-publisher` (via `network/vpc`) | Tenant databases, ALBs, and ECS/EKS worker nodes fail to launch. |
| `vpc/database_subnets` | Comma-delimited list of database subnet IDs | String | `governance/discovery-publisher` (via `network/vpc`) | Tenant database module (`data/postgres`) cannot create DB subnet groups. |
| `eks/cluster_name` | Name of the EKS cluster | String | `governance/discovery-publisher` (via `compute/eks`) | Workload CI/CD and Argo CD cluster Secret generators cannot address the cluster. |
| `eks/oidc_provider_arn` | EKS OIDC provider ARN | String | `governance/discovery-publisher` (via `compute/eks`) | Tenant IRSA and Pod Identity IAM role vending fails. |
| `eks/cluster_endpoint` | EKS Kubernetes API endpoint URL | String | `governance/discovery-publisher` (via `compute/eks`) | Argo CD GitOps controllers and external CI runners cannot communicate with the cluster. |
| `eks/cluster_ca_data` | Base64-encoded cluster certificate authority | String | `governance/discovery-publisher` (via `compute/eks`) | TLS verification fails for Kubernetes API clients and Argo CD cluster secrets. |
| `eks/karpenter_node_role` | IAM role name (not ARN) for Karpenter EC2 nodes | String | `governance/discovery-publisher` (via `compute/eks`) | Karpenter `EC2NodeClass.spec.role` fails; dynamic node autoscaling fails to provision nodes. |
| `eks/karpenter_queue_name` | SQS queue name for Karpenter interruption events | String | `governance/discovery-publisher` (via `compute/eks`) | Karpenter graceful spot interruption handling is disabled or fails to reconcile. |
| `ack/cross_account_role_arn` | ACK controller cross-account role ARN | String | `governance/discovery-publisher` (via `identity/ack-cross-account`) | Hub-and-spoke ACK controller cannot vend cloud resources into the tenant account. |
| `account/id` | The account's 12-digit AWS account ID | String | `governance/account-baseline` | Cross-account trust policies, bucket policies, and audit trails fail resolution. |
| `account/ou` | AWS Organizations OU name (e.g. `Workloads/Prod`) | String | `governance/account-baseline` | Environment-aware conditional provisioning and showback tagging fail. |
| `kms/general_key_arn` | Customer-managed KMS key ARN for general data | String | `governance/account-baseline` | S3, SQS, and EBS encryption fail compliance gates requiring CMKs. |
| `kms/confidential_key_arn` | Customer-managed KMS key ARN for confidential data | String | `governance/account-baseline` | Databases and confidential storage fail regulatory encryption standards. |
| `iam/workload_boundary_arn` | ARN of `platform-workload-boundary` | String | `governance/account-baseline` | Tenant IAM role creation fails (SCP enforces `iam:PermissionsBoundary`). |
| `iam/developer_policy_arn` | ARN of `platform-developer` policy | String | `governance/account-baseline` | Developer Identity Center permission set role delegation fails. |

---

## 2. API Contract Rules & Versioning Policy

The discovery contract is treated as a **versioned API**:

1. **Only Add, Never Break**:
   - Parameters may be added at any time with backwards-compatible defaults.
   - Renaming, removing, or changing the schema/format of an existing parameter is a **breaking change** and is strictly prohibited within the `/platform/v1/` (default `/platform/`) namespace.
   - Breaking revisions must be introduced under a new versioned prefix (e.g. `/platform/v2/${env}/...`), and the legacy path must be published concurrently for at least one major release lifecycle.
2. **Single Publisher Ownership**:
   - `governance/discovery-publisher` is the single authoritative writer of stack outputs (VPC, EKS, ACK). Subordinate modules (`network/vpc`, `compute/eks`) do not create their own duplicate SSM parameters.
   - `governance/account-baseline` is the single authoritative writer of account-level foundation metadata (account ID, OU, KMS CMKs, workload boundaries).
3. **Non-Sensitive Metadata Only**:
   - Contract parameters are public within the AWS account (IAM type `String`, not `SecureString`). No secrets, private keys, or passwords are ever published to the contract.
4. **Machine-Readable Schema**:
   - The contract is defined in `docs/discovery-contract.json` and validated by CI scripts (`workloads-live-repo/scripts/check_discovery_contract.py`).

---

## 3. Multi-Tool Consumption Examples

Tenant developers consume the discovery contract using their preferred IaC tool without needing platform admin privileges:

### 3.1 Terraform / OpenTofu
```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/platform/${var.env}/${var.region}/vpc/id"
}

data "aws_ssm_parameter" "kms_key" {
  name = "/platform/${var.env}/${var.region}/kms/general_key_arn"
}

resource "aws_s3_bucket" "app_storage" {
  bucket = "my-team-app-${var.env}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_storage" {
  bucket = aws_s3_bucket.app_storage.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = data.aws_ssm_parameter.kms_key.value
      sse_algorithm     = "aws:kms"
    }
  }
}
```

### 3.2 AWS CDK (TypeScript)
```typescript
import * as cdk from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

export class TenantStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const env = process.env.ENVIRONMENT || 'dev';
    const region = this.region;

    // Lookup VPC ID dynamically from SSM Discovery Contract
    const vpcId = ssm.StringParameter.valueForStringParameter(
      this,
      `/platform/${env}/${region}/vpc/id`
    );

    const vpc = ec2.Vpc.fromLookup(this, 'PlatformVpc', {
      vpcId: vpcId,
    });
  }
}
```

### 3.3 Pulumi (Python)
```python
import pulumi
import pulumi_aws as aws

config = pulumi.Config()
env = config.get("env") or "dev"
region = aws.get_region().name

# Retrieve EKS cluster name and endpoint from discovery contract
cluster_name_param = aws.ssm.get_parameter(
    name=f"/platform/{env}/{region}/eks/cluster_name"
)
cluster_endpoint_param = aws.ssm.get_parameter(
    name=f"/platform/{env}/{region}/eks/cluster_endpoint"
)

pulumi.export("eks_cluster_name", cluster_name_param.value)
pulumi.export("eks_cluster_endpoint", cluster_endpoint_param.value)
```
