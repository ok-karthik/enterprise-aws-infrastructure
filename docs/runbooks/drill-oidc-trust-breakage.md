# Drill Plan: CI/CD OIDC Trust Breakage

- **Target Area**: Authentication & CI/CD Pipelines
- **Target Roles**: `github-actions-plan`, `github-actions-apply`
- **Relevant Controls**: SOC 2 CC6.1, ISO 27001 A.5.15

---

## 1. Goal

Validate the system behavior when GitHub Actions OpenID Connect (OIDC) token claims fail to match the AWS IAM role trust policy, verify that authentication fails closed, confirm the diagnostic trail in CloudTrail, and practice restoring the trust policy.

---

## 2. Steps to Execute

1. **Simulate Mismatched Trust Policy**:
   In a sandbox or test member account, update the IAM trust policy of `github-actions-plan` to expect an invalid subject claim (e.g. modify the `token.actions.githubusercontent.com:sub` condition to a non-existent repo or branch):
   ```bash
   aws iam update-assume-role-policy \
     --role-name github-actions-plan \
     --policy-document file://broken-trust-policy.json
   ```

2. **Trigger CI/CD Pipeline**:
   Trigger an automated GitHub Actions workflow run (or run `aws sts assume-role-with-web-identity` locally with a valid GitHub OIDC token).

3. **Diagnose via CloudTrail**:
   In the target member account, query CloudTrail for failed role assumption events:
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
     --max-results 5
   ```

---

## 3. What You Expect to See

- The GitHub Actions workflow fails during the `setup-platform` or AWS credentials configuration step.
- Error message in pipeline logs: `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`.
- CloudTrail confirms the attempt was denied with `errorMessage: "Not authorized to perform sts:AssumeRoleWithWebIdentity"`.
- No credentials or sensitive environment details are leaked.

---

## 4. How to Roll Back

1. **Restore Role Trust Policy**:
   Re-apply the original trusted policy using the CloudFormation template:
   ```bash
   aws iam update-assume-role-policy \
     --role-name github-actions-plan \
     --policy-document file://restored-trust-policy.json
   ```
2. **Re-run the Pipeline**:
   Re-run the failed GitHub Actions job and verify that role assumption succeeds cleanly.

---

## 5. Drill Results & Observations (Filled during live drill)

*(To be recorded by engineer during S6 live drill: exact error message, CloudTrail event fields, and observed debugging friction).*
