# Runbook & Postmortem: Bad SCP Rollout & Emergency Rollback Drill

- **Severity**: P1 / Critical
- **Target Area**: AWS Organizations / Service Control Policies (SCPs)
- **Relevant Controls**: SOC 2 CC6.1, ISO 27001 A.5.15, A.8.32

---

## 1. Overview & Failure Mode

Service Control Policies (SCPs) are organizational guardrails that override all IAM permissions in member accounts. An overly broad or syntactically erroneous SCP can instantly lock member accounts out of critical AWS services, halting application traffic, deployments, or backups.

Example failure symptom:
```
An error occurred (AccessDeniedException) when calling the RunInstances operation:
User: arn:aws:sts::111122223333:assumed-role/github-actions-apply/run is not authorized
to perform: ec2:RunInstances with an explicit deny in a service control policy
```

---

## 2. Immediate Diagnostic Steps

1. **Identify the Deny Signature**:
   - Check CloudTrail event records in the failing account.
   - Look for `"errorCode": "Client.UnauthorizedOperation"` or `"AccessDenied"` with the explicit message:
     `explicit deny in a service control policy`.
2. **Identify the Attached SCPs**:
   - Run from the management account or via `BreakGlassAdmin`:
     ```bash
     aws organizations list-policies-for-target \
       --target-id <affected-ou-or-account-id> \
       --filter SERVICE_CONTROL_POLICY
     ```
3. **Verify Canary Target**:
   - Verify whether the failure is isolated to the canary **Policy-Staging OU** or has breached production.

---

## 3. Emergency Rollback Procedure

### Step 1: Detach the Errant SCP Immediately
From the management account using the AWS CLI or console:
```bash
aws organizations detach-policy \
  --target-id <affected-ou-id> \
  --policy-id <errant-policy-id>
```
*Note*: As long as the default `FullAWSAccess` policy remains attached to the OU, detaching the errant custom SCP immediately restores normal operation within seconds.

### Step 2: Revert via GitOps
1. Open a Git Pull Request reverting the change in `foundation-live-repo/management/_global/governance/organization/policies/`.
2. Ensure the policy is restricted to `guardrail_target_ous = ["Policy-Staging"]` in `foundation-live-repo/_envcommon/governance/organization.hcl`.
3. Apply the corrected configuration through the management CI/CD pipeline or via authenticated human apply.

---

## 4. Blameless Postmortem (Drill Simulation)

### Incident Summary
A newly introduced SCP intended to enforce IMDSv2 accidentally lacked a condition check for Auto Scaling launch templates, causing all EC2 instance launches in the targeted OU to fail immediately with an explicit SCP deny.

### Root Cause
The policy statement used a blanket `Deny` on `ec2:RunInstances` without qualifying `ec2:Attribute/MetadataHttpTokens = optional`. It also omitted exemptions for AWS service-linked roles and the CloudFormation StackSets execution role.

### What Went Well
- **Canary Policy-Staging OU Protection**: Because `guardrail_target_ous` defaulted to `["Policy-Staging"]` (PLAN 4.6), the bad policy was tested on non-critical canary resources first. Production workloads were completely unaffected.
- **Fast Detachment**: Detaching the policy via the AWS Organizations API restored normal operations in less than 45 seconds without needing to wait for a full Terraform apply.

### Preventive Actions
1. Mandated automated unit tests (`tests/organization.tftest.hcl`) evaluating policy JSON rendered structure against mock AWS API calls.
2. Formalized the rule that no SCP may be attached to `Workloads/Prod` without a mandatory 72-hour soak period in `Policy-Staging`.
