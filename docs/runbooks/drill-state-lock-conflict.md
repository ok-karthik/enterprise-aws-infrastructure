# Runbook & Postmortem: S3 State Lock Contention & Conflict Drill

- **Severity**: P2 / Medium
- **Target Area**: Terragrunt / Terraform State Storage
- **Relevant Controls**: SOC 2 CC8.1, ISO 27001 A.8.32

---

## 1. Overview & Failure Mode

This platform utilizes S3 native state locking (`use_lockfile = true` introduced in Terraform 1.10+ / Terragrunt 1.0+), eliminating external DynamoDB tables.

When an automated apply or local debugging session terminates abnormally (e.g. runner spot interruption, runner cancellation, or SIGKILL), an orphaned `.tflock` file can remain in the target S3 state bucket:
```
Error: Error acquiring the state lock
Lock Info:
  ID:        1727632800-4b2a9e8f-7c1d-4ef1
  Path:      tg-state-111122223333/workloads-dev/eu-central-1/compute/eks/terraform.tfstate
  Operation: OperationTypeApply
  Who:       runner@fv-az123-456
  Version:   1.15.1
  Created:   2026-09-29 14:00:00.123456789 +0000 UTC
  Info:
```

Subsequent PR plans and applies fail immediately because the lock cannot be acquired.

---

## 2. Immediate Diagnostic Steps

1. **Verify No Concurrent Apply is Running**:
   - Check GitHub Actions: Ensure no active workflow run is currently applying changes to the specified account and component.
   - **Crucial Rule**: Never unlock state while another process is writing. Doing so causes state corruption.
2. **Inspect Lock Details**:
   - Extract the `Lock Info ID` (e.g. `1727632800-4b2a9e8f-7c1d-4ef1`).
   - Extract the `Path` to identify the exact state key in the S3 bucket.

---

## 3. Recovery Procedure

### Automated Retry (Standard Behavior)
`root.hcl` injects `-lock-timeout=5m` for all plan and apply operations (PLAN 8.3). Transient locks held during short parallel runs resolve automatically within 5 minutes.

### Manual Safe Force-Unlock (Human SRE Intervention)
If the lock is confirmed orphaned:

1. Assume the appropriate administrative role (`PlatformEngineer` or `BreakGlassAdmin` for production).
2. Navigate to the module's leaf directory:
   ```bash
   cd workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/compute/eks
   ```
3. Execute `terragrunt force-unlock`:
   ```bash
   terragrunt force-unlock 1727632800-4b2a9e8f-7c1d-4ef1
   ```
4. Verify state integrity:
   ```bash
   terragrunt plan
   ```

> [!WARNING]
> **Autonomous Agent Constraint**: The local agent guardrail (`.agents/hooks/guard.py`) explicitly **blocks** AI agents from running `force-unlock` automatically. Only authenticated human engineers may clear state locks after verifying process isolation.

---

## 4. Blameless Postmortem (Drill Simulation)

### Incident Summary
A CI/CD apply job for `compute/eks` was cancelled mid-flight by a contributor pushing a new commit to the branch. The subsequent build failed with `Error acquiring the state lock`.

### Root Cause
Cancelling the GitHub Actions runner sent an immediate `SIGTERM` followed by `SIGKILL` before Terraform's graceful exit handler could delete the lockfile in S3.

### What Went Well
- S3 native state locking prevented concurrent modifications from conflicting or corrupting state.
- The 5-minute timeout prevented immediate cascading failures for transient locks.
- Agent guardrails prevented the pipeline healer agent from prematurely force-unlocking an active state.

### Preventive Actions
1. Configured GitHub Actions `concurrency` groups with `cancel-in-progress: false` on apply workflows to prevent mid-execution cancellations.
2. Documented the force-unlock runbook and updated the SRE error-budget metrics.
