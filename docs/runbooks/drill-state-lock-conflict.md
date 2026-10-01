# Drill Plan: S3 State Lock Contention & Conflict Recovery

- **Target Area**: Terragrunt / Terraform State Storage
- **Backend Architecture**: S3 Native State Locking (`use_lockfile = true`)
- **Relevant Controls**: SOC 2 CC8.1, ISO 27001 A.8.32

---

## 1. Goal

Validate that S3 native state locking correctly detects concurrent access, verify the behavior of the automated retry mechanism (`-lock-timeout=5m`), and practice safe manual lock investigation and force-unlock procedures when an orphaned lock is encountered.

---

## 2. Steps to Execute

1. **Simulate an Orphaned State Lock**:
   In a test leaf stack (e.g., `workloads-dev`), acquire an intentional state lock or simulate a crashed process by creating a temporary lock object in the state S3 bucket:
   ```bash
   aws s3 cp test.tflock s3://tg-state-<account-id>-<region>/<state-path>.tflock
   ```

2. **Trigger Concurrent Plan**:
   Execute a plan on the same leaf component:
   ```bash
   terragrunt plan
   ```

3. **Inspect Lock Contention**:
   Observe whether the process waits up to 5 minutes as configured by `root.hcl`'s `-lock-timeout=5m`. Once the timeout expires, capture the lock details from stderr.

---

## 3. What You Expect to See

- During the 5-minute timeout window: Terragrunt logs periodic lock retry attempts.
- After the timeout: Terragrunt exits with an error:
  `Error: Error acquiring the state lock`
  accompanied by `Lock Info: ID: <lock-id>, Path: <state-path>, Operation: <operation>, Who: <user/runner>`.
- State integrity is preserved; no partial writes or state corruption occur.

---

## 4. How to Roll Back

1. **Process Isolation Verification**:
   Verify that no CI workflow run or background process is actively executing against the state path. **Never force-unlock an active run.**

2. **Manual Force-Unlock**:
   As an authenticated human operator (`PlatformEngineer` or `BreakGlassAdmin`), run:
   ```bash
   terragrunt force-unlock <lock-id>
   ```

3. **Verify State Health**:
   Execute `terragrunt plan` to confirm that state locking functions normally and the environment is clean.

---

## 5. Drill Results & Observations (Filled during live drill)

*(To be recorded by engineer during S6 live drill: exact retry behavior, time to detect, and verification after force-unlock).*
