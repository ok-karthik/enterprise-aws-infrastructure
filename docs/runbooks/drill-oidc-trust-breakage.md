# Runbook & Postmortem: CI/CD OIDC Trust Breakage Drill

- **Severity**: P1 / High
- **Target Area**: Authentication & CI/CD Pipelines
- **Relevant Controls**: SOC 2 CC6.1, ISO 27001 A.5.15

---

## 1. Overview & Failure Mode

GitHub Actions relies on **zero-key OpenID Connect (OIDC)** authentication to assume `github-actions-plan` and `github-actions-apply` roles in target AWS accounts.

A failure occurs when the GitHub OIDC token claims (specifically the `sub` claim) fail to match the AWS IAM role trust policy condition:
```
Error: Credentials could not be loaded, please check your action inputs:
Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

---

## 2. Immediate Diagnostic Steps

1. **Inspect GitHub Actions Run Context**:
   - Check the triggering event: Is it a `pull_request`, `push`, or `workflow_dispatch`?
   - Note the branch ref: `refs/heads/<branch>` vs `refs/pull/<pr>/merge`.
2. **Review CloudTrail in the Target Account**:
   - Run the following AWS CLI query in the target workload account:
     ```bash
     aws cloudtrail lookup-events \
       --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
       --max-results 5
     ```
   - Look for `errorMessage: "Not authorized to perform sts:AssumeRoleWithWebIdentity"`.
3. **Verify the Role Trust Policy**:
   - Check the role trust document:
     ```bash
     aws iam get-role --role-name github-actions-plan --query 'Role.AssumeRolePolicyDocument'
     ```
   - Compare the condition `token.actions.githubusercontent.com:sub` with the GitHub repository context:
     - `repo:ok-karthik/enterprise-aws-infrastructure:pull_request`
     - `repo:ok-karthik/enterprise-aws-infrastructure:ref:refs/heads/main`
     - `repo:ok-karthik/enterprise-aws-infrastructure:environment:<env>`

---

## 3. Recovery Procedure

1. **Temporary Mitigation (if blocked)**:
   - If an emergency apply is blocked during a production incident, assume `BreakGlassAdmin` via AWS IAM Identity Center and run the deployment locally.
2. **Permanent Fix**:
   - Update the CloudFormation bootstrap template: `foundation-live-repo/_bootstrap/cloudformation/account-bootstrap.yaml`.
   - Ensure the `StringLike` or `StringEquals` pattern matches the actual repo naming and branch syntax:
     ```yaml
     Condition:
       StringEquals:
         token.actions.githubusercontent.com:aud: "sts.amazonaws.com"
       StringLike:
         token.actions.githubusercontent.com:sub:
           - !Sub "repo:${GitHubOrg}/${GitHubRepo}:pull_request"
           - !Sub "repo:${GitHubOrg}/${GitHubRepo}:ref:refs/heads/*"
     ```
   - Roll out the change across member accounts via `governance/bootstrap-stacksets`.

---

## 4. Blameless Postmortem (Drill Simulation)

### Incident Summary
During an infrastructure upgrade, the repository was migrated/forked, causing all automated CI/CD plan jobs on open Pull Requests to fail with `AssumeRoleWithWebIdentity` access denied errors.

### Root Cause
The IAM role trust policy in member accounts contained a hardcoded GitHub organization path (`repo:ok-karthik/enterprise-aws-infrastructure:*`). When a contributor ran tests from an external fork or renamed branch, the `sub` claim did not match, triggering an immediate security drop.

### What Went Well
- The IAM trust policy failed closed, correctly rejecting tokens that did not match the expected repository identity.
- No static AWS secrets were exposed or leaked.

### What Went Wrong
- The error message in GitHub Actions was opaque, requiring CloudTrail investigation to determine the exact subject mismatch.

### Preventive Actions
1. Documented standard OIDC claim structures in `docs/CICD.md`.
2. Created a pre-flight script in `.github/actions/setup-platform/action.yml` that prints the sanitized JWT subject claim on failure to speed up debugging.
