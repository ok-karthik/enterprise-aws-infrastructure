# Drill Plan: Bad SCP Rollout & Emergency Rollback

- **Target Area**: AWS Organizations / Service Control Policies (SCPs)
- **Target OU**: `Policy-Staging` (Canary)
- **Relevant Controls**: SOC 2 CC6.1, ISO 27001 A.5.15, A.8.32

---

## 1. Goal

Validate that an errant or overly broad Service Control Policy (SCP) is safely contained within the canary `Policy-Staging` OU, confirm how the failure presents in CloudTrail and the AWS CLI, and verify that emergency manual detachment restores service within seconds before reverting through GitOps.

---

## 2. Steps to Execute

1. **Simulate Bad Policy in Canary**:
   From the management account, attach a restrictive SCP statement (e.g., blocking `ec2:RunInstances` without proper condition exclusions) to the `Policy-Staging` OU:
   ```bash
   aws organizations attach-policy \
     --target-id <policy-staging-ou-id> \
     --policy-id <test-policy-id>
   ```

2. **Trigger Action in Member Account**:
   Attempt an EC2 launch or `terragrunt plan` in a member account within `Policy-Staging`.

3. **Diagnose via CloudTrail**:
   Inspect CloudTrail events in the member account to verify the error code and exact deny statement:
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
     --max-results 5
   ```

---

## 3. What You Expect to See

- The CLI/Terraform operation fails with `AccessDenied` / `Client.UnauthorizedOperation`.
- The error explicitly states: `with an explicit deny in a service control policy`.
- Workload accounts outside `Policy-Staging` remain completely unaffected.

---

## 4. How to Roll Back

1. **Immediate Emergency Detachment**:
   Detach the errant policy directly from the management account:
   ```bash
   aws organizations detach-policy \
     --target-id <policy-staging-ou-id> \
     --policy-id <test-policy-id>
   ```
   *Note*: As long as `FullAWSAccess` remains attached, normal operation is restored immediately upon detachment.

2. **GitOps Reconciliation**:
   - Revert the Git commit that introduced the policy in `foundation-live-repo/management/_global/governance/organization/policies/`.
   - Run Terragrunt in the management organization stack to reconcile desired state with AWS.

---

## 5. Drill Results & Observations (Filled during live drill)

*(To be recorded by engineer during S6 live drill: exact error message, observed time to recovery, and any unexpected behaviors).*
