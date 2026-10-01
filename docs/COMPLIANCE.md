# Compliance & Regulatory Control Matrix

This document provides a verifiable mapping of core regulatory frameworks (**SOC 2 Type II**, **ISO/IEC 27001:2022**, and **GDPR**) to the automated controls, Terraform/Terragrunt modules, policies, and audit evidence implemented across this enterprise AWS platform.

---

## 1. Compliance Architecture & Evidence Retention

All infrastructure changes are managed strictly as code through GitOps pipelines. Auditors can verify compliance through:
1. **Immutable Log Archive**: Centralized in the `log-archive` account with S3 Object Lock in `COMPLIANCE` mode (default 400-day retention).
2. **Deterministic CI/CD Artifacts**: GitHub Actions plans are generated as `plan.json`, evaluated by policy engines (OPA Rego + Checkov), and retained for **400 days** as verifiable build artifacts (`plans-${account}`).
3. **Multi-Account Segregation**: Workload isolation across distinct AWS Organizations OUs (`Security`, `Infrastructure`, `Workloads`, `Sandbox`).

---

## 2. Master Control Mapping Matrix

| Framework Control | Control Description | How Met (Module / Guardrail / CI Gate) | Audit Evidence Location |
|---|---|---|---|
| **SOC 2 CC6.1** / **ISO 27001 A.5.15, A.5.16, A.5.18** | Logical Access Control & Identity Management | `identity/identity-center` provisions role-based access; zero static IAM user credentials allowed via SCP (`deny_iam_user_creation`); workload auth via `identity/workload-identity` (EKS Pod Identity). | AWS IAM Identity Center console; AWS Organizations SCP list; CloudTrail event `CreateUser` (denied). |
| **SOC 2 CC6.2** / **ISO 27001 A.5.18** | User Access Provisioning & Deprovisioning | Centralized SCIM group synchronization in `identity-center`; permission sets bound strictly to IdP groups; temporary elevated sessions expire in 1 hour. | IdP audit logs; IAM Identity Center assignments in `foundation-live-repo/management/_global/identity/identity-center/`. |
| **SOC 2 CC6.3** / **ISO 27001 A.8.2** | Privileged Access Management & Just-in-Time Access | No standing admin access in Production; `BreakGlassAdmin` permission set requires just-in-time elevation and triggers instant alerts via `security/break-glass-alerts`. | CloudWatch Logs `/aws/events/break-glass`; SNS subscription delivery logs; CloudTrail `AssumeRoleWithSAML`. |
| **SOC 2 CC6.6** / **ISO 27001 A.8.20, A.8.21, A.8.22** | Network Security, Perimeter Defense & Boundary Segregation | `network/vpc` with private/database subnets, deny-all default NACLs; central egress inspection via `network/inspection-egress` (AWS Network Firewall); VPC Block Public Access enforced by `governance/account-baseline`. | VPC route tables; Network Firewall rule group metrics; AWS Config rule `vpc-default-security-group-closed`. |
| **SOC 2 CC6.7** / **ISO 27001 A.8.24** | Data Transmission Cryptography (Encryption in Transit) | Resource Control Policies (RCPs) in `governance/data-perimeter` enforce `aws:SecureTransport` for S3, SQS, KMS, Secrets Manager; EKS API and cluster endpoints enforce TLS 1.2+. | SCP/RCP JSON definitions; CloudTrail S3 access logs showing HTTPS-only status codes; OPA policy `deny_insecure_transport.rego`. |
| **SOC 2 CC6.8** / **ISO 27001 A.8.7** | Malware Protection & Vulnerability Management | `security/threat-detection` enables GuardDuty (Malware Protection for EBS/S3, EKS Runtime Monitoring) and Inspector v2 for EC2, ECR, and Lambda across all member accounts. | Security Hub aggregated dashboard (in `security-tooling`); GuardDuty finding console; Inspector vulnerability reports. |
| **SOC 2 CC7.1** / **ISO 27001 A.8.16** | Infrastructure Configuration & Vulnerability Monitoring | Organization-wide Security Hub standards (AWS Foundational Security Best Practices v1.0.0 & CIS AWS Foundations Benchmark v3.0.0) aggregated to `primary_region`. | Security Hub compliance scores; Inspector CVE findings; GitHub Actions SARIF security tab. |
| **SOC 2 CC7.2** / **ISO 27001 A.8.15** | Logging, Audit Trails & Event Monitoring | `security/org-cloudtrail` multi-region trail with log validation enabled; `security/log-archive` Object Lock (400d retention); VPC Flow Logs enabled on all VPC subnets. | S3 bucket `s3://tg-log-archive-cloudtrail-*` with Object Lock retention; CloudTrail log validation status: `aws cloudtrail validate-logs`. |
| **SOC 2 CC7.3** / **ISO 27001 A.5.24 - A.5.28** | Security Incident Response & Auto-Remediation | `security/security-alerts` routes GuardDuty (severity >= 7) and Security Hub (HIGH/CRITICAL) to SNS/SIEM; `security/auto-remediation` Lambda automatically strips open SSH/RDP ingress rules in < 30s. | CloudWatch metric `AutoRemediationExecutionTime`; Lambda CloudWatch Logs; SNS alert notifications; incident runbooks in `docs/runbooks/auto-remediation.md`. |
| **SOC 2 CC8.1** / **ISO 27001 A.8.32** | Change Management, Peer Review & Segregation of Duties | All infra changes require GitHub Pull Requests with mandatory peer review (`CODEOWNERS`); plan-stage static analysis (TFLint, Checkov, OPA Rego); separate apply role trusted only from protected GitHub Environment. | GitHub Pull Request history; GitHub Actions workflow run logs (`terragrunt.yml`); 400-day retained `plans-${account}` artifacts; Git signed commits. |
| **ISO 27001 A.8.13** | Information Backup, Redundancy & Disaster Recovery | `data/backup` AWS Backup policies with Vault Lock; `data/aurora-postgres` cross-region replication; S3 cross-region replication to secondary region (`eu-west-1`); Route 53 health check failover. | AWS Backup vault recovery points; Aurora global database cluster replication status; disaster recovery drill logs in `docs/DISASTER_RECOVERY.md`. |

---

## 3. GDPR (General Data Protection Regulation - Art. 25, 32, 44–49)

* **Data Residency & Geographic Fencing**:
  * **Enforcement**: Service Control Policy (`foundation-live-repo/management/_global/governance/organization/policies/region_allowlist.json.tftpl`) explicitly blocks any resource creation outside approved EU regions:
    * **Primary Region**: `eu-central-1` (Frankfurt, Germany) — all production data processing, EKS clusters, and transactional databases.
    * **Secondary / DR Region**: `eu-west-1` (Dublin, Ireland) — read replicas, backup storage, and warm standby infrastructure.
  * **Data Perimeter**: Resource Control Policies (RCPs) deny access to S3, KMS, SQS, and Secrets Manager from any principal outside the AWS Organization, preventing cross-border exfiltration or unauthorized third-party access.
  * **PII Discovery**: AWS Macie is configured in `security-tooling` to continuously scan buckets tagged `DataClassification=confidential` or `DataClassification=restricted` for PII and personal data identifiers.

---

## 4. Auditor Evidence Gathering Guide

When requested by compliance auditors (SOC 2, ISO 27001), collect evidence using the following commands:

```bash
# 1. Verify CloudTrail Log File Integrity
aws cloudtrail validate-logs \
  --trail-arn arn:aws:cloudtrail:eu-central-1:<management-account-id>:trail/org-cloudtrail \
  --start-time $(date -v -30d +%Y-%m-%dT00:00:00Z)

# 2. Verify S3 Object Lock Compliance Mode on Log Archive
aws s3api get-object-lock-configuration \
  --bucket tg-log-archive-cloudtrail-<account-id>

# 3. Verify Account Regional Guardrail SCP Attachment
aws organizations list-policies-for-target \
  --target-id <workloads-prod-ou-id> \
  --filter SERVICE_CONTROL_POLICY

# 4. Export Security Hub FSBP / CIS Compliance Findings
aws securityhub get-findings \
  --filters '{"ComplianceStatus": [{"Value": "FAILED", "Comparison": "EQUALS"}]}' \
  --region eu-central-1
```
