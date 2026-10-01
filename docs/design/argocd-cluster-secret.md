# Argo CD Spoke Cluster Secret Architecture

This document describes how the **Internal Developer Platform (IDP)** and Argo CD GitOps engine dynamically consume the **Discovery Contract** (`docs/DISCOVERY_CONTRACT.md`) to register and manage workload EKS clusters.

---

## 1. Architectural Overview

In a multi-account hub-and-spoke platform:
1. **Infrastructure Layer (This Repo)**: Provisions the EKS cluster in the workload account, configures Karpenter roles/queues, and publishes metadata into SSM Parameter Store via `governance/discovery-publisher`.
2. **Synchronization Layer (External Secrets Operator)**: Runs in the hub cluster (or workload spoke) and synchronizes SSM parameters into native Kubernetes `Secret` resources.
3. **Application Delivery Layer (Argo CD)**: Uses label selectors to target workload clusters for GitOps application deployments.

```
+-------------------------------------------------------------+
| Workload Account (Spoke)                                    |
|                                                             |
|   [compute/eks]                                             |
|        │                                                    |
|        ▼                                                    |
|   [discovery-publisher]                                     |
|        │                                                    |
|        ▼                                                    |
|   AWS SSM Parameter Store                                   |
|   - /platform/{env}/{region}/eks/cluster_name               |
|   - /platform/{env}/{region}/eks/cluster_endpoint           |
|   - /platform/{env}/{region}/eks/cluster_ca_data            |
|   - /platform/{env}/{region}/eks/karpenter_node_role        |
|   - /platform/{env}/{region}/eks/karpenter_queue_name       |
+------------------------------▲------------------------------+
                               │
               (SSM Read via IAM / OIDC)
                               │
+------------------------------┴------------------------------+
| Shared Services Account (Hub)                               |
|                                                             |
|   [External Secrets Operator]                               |
|        │ fetches parameters                                 |
|        ▼                                                    |
|   Kubernetes Secret (argocd.argoproj.io/secret-type=cluster)|
|        │ reconciles targets                                 |
|        ▼                                                    |
|   [Argo CD Application Controller]                          |
|        │ deploy GitOps manifests                            |
|        ▼                                                    |
|   Spoke EKS Kubernetes API                                  |
+-------------------------------------------------------------+
```

---

## 2. Argo CD Cluster Secret Schema

Argo CD identifies target deployment clusters by reading Kubernetes `Secret` objects carrying the label `argocd.argoproj.io/secret-type: cluster`.

### 2.1 Generated Secret Manifest

The IDP engine assembles the cluster registration secret from the Discovery Contract:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-workloads-dev-eu-central-1
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: dev
    region: eu-central-1
    tier: workload
    karpenter: enabled
  annotations:
    platform.io/karpenter-node-role: "workloads-dev-karpenter-node"
    platform.io/karpenter-queue: "workloads-dev-karpenter"
    platform.io/discovery-version: "v1"
type: Opaque
stringData:
  name: "workloads-dev-eks"
  server: "https://72AB31899CDE12345.gr7.eu-central-1.eks.amazonaws.com"
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
      },
      "awsAuthConfig": {
        "clusterName": "workloads-dev-eks",
        "roleARN": "arn:aws:iam::111122223333:role/argocd-spoke-manager"
      }
    }
```

### 2.2 Parameter-to-Field Mapping

| Secret Field / Metadata | Source Discovery Contract Parameter | Purpose |
|---|---|---|
| `stringData.name` | `/platform/${env}/${region}/eks/cluster_name` | Unique cluster identifier in Argo CD CLI and UI |
| `stringData.server` | `/platform/${env}/${region}/eks/cluster_endpoint` | Kubernetes API endpoint |
| `stringData.config.tlsClientConfig.caData` | `/platform/${env}/${region}/eks/cluster_ca_data` | Root CA certificate for API server TLS verification |
| `annotations."platform.io/karpenter-node-role"` | `/platform/${env}/${region}/eks/karpenter_node_role` | Consumed by Karpenter `EC2NodeClass.spec.role` |
| `annotations."platform.io/karpenter-queue"` | `/platform/${env}/${region}/eks/karpenter_queue_name` | Consumed by Karpenter interruption controller |
| `labels.environment` | Derived from path `<env>` | Used by Argo CD ApplicationSets for environment targeting |
| `labels.region` | Derived from path `<region>` | Used by Argo CD ApplicationSets for regional targeting |

---

## 3. Hub-to-Spoke Authentication (Design Analysis)

> [!NOTE]
> **Implementation Status**: Cross-account hub-to-spoke authentication is an architectural design contract; live cluster-to-cluster authentication has **not yet been verified against real AWS accounts**.

### Recommended Approach: AWS IAM Access Entries + Cross-Account STS AssumeRole

To authenticate the hub Argo CD instance against spoke clusters securely without long-lived tokens:

1. **Hub Workload Identity**:
   - The Argo CD application controller pod in the `shared-services` hub cluster runs with an IAM Pod Identity / IRSA role (`arn:aws:iam::<hub-account-id>:role/argocd-hub-controller`).
2. **Spoke IAM Role**:
   - In each workload spoke account, create an IAM role `argocd-spoke-manager` whose trust policy permits `sts:AssumeRole` only from `arn:aws:iam::<hub-account-id>:role/argocd-hub-controller`.
3. **EKS Access Entry (API-Native)**:
   - In the spoke cluster (`iac-modules-repo/identity/human-access` or `compute/eks`), register an `aws_eks_access_entry` for `arn:aws:iam::<spoke-account-id>:role/argocd-spoke-manager` with the `AmazonEKSClusterAdminPolicy` access policy association.
4. **Argo CD Exec Provider**:
   - Argo CD uses the native `awsAuthConfig` in its cluster secret (or `aws-iam-authenticator` / AWS CLI v2 `aws eks get-token`) to assume `argocd-spoke-manager` across accounts and obtain a short-lived bearer token (15-minute expiry).

### Alternative Rejected Approaches

*   **Static ServiceAccount Tokens**: Rejected due to high security risk (indefinite validity, credential rotation burden, violation of SOC 2 CC6.1).
*   **Direct OIDC Cross-Cluster Federation**: Complex network requirement requiring public OIDC discovery endpoints and cluster CA management across disparate AWS Organizations OUs.
