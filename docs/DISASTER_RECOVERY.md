# 🚑 Disaster Recovery & Failure Modes

> **Status:** Design, not measured yet. RTO/RPO targets and failover procedures reflect architectural targets and will be verified during live drills.

In an enterprise Infrastructure-as-Code (IaC) environment, failures happen. This document explicitly outlines our philosophy on handling failed deployments, state corruption, and rollback strategies.

## 1. The Rollback Philosophy: "Roll-Forward"

**Question:** *What is our rollback strategy if a deployment fails or breaks the environment?*

**Answer:** **We do NOT "Rollback." We Roll-Forward.**

In traditional software, rolling back is as simple as deploying the previous artifact. In Terraform/Terragrunt, attempting to revert a commit after a partial or failed deployment forces Terraform to attempt to destroy newly (or partially) created resources. This often results in a catastrophic failure loop, as AWS APIs may not allow the destruction of resources that are stuck in a transitioning state.

### The Roll-Forward Procedure
1. **Identify the Failure:** Read the CI/CD pipeline logs to find the exact AWS API error (e.g., "Timeout waiting for EKS cluster", "IAM Role already exists").
2. **Fix the Code:** Push a new commit to the PR that corrects the issue.
3. **Re-Apply:** Allow the pipeline to run the updated plan. Terraform's declarative nature will automatically reconcile the partial state with the new desired state.

## 2. Failure Mode: "Apply Fails Halfway"

**Question:** *What happens to the infrastructure and state if `terragrunt apply` times out or fails halfway through?*

**Answer:**
Because we use the **S3 backend with native locking** (`use_lockfile = true`, no DynamoDB table), the state is protected.
1. When the apply starts, Terraform writes a `<state key>.tflock` object next to the state file.
2. If the apply fails halfway, Terraform writes the *partial* state of the successfully created resources to S3 before exiting.
3. The lock object is deleted.
4. The infrastructure is now in a "partial" state, but the **state file accurately reflects this reality**.
5. The next `terragrunt plan` will read the partial state and simply pick up where it left off.

## 3. Handling Locked State Files

Occasionally, a catastrophic runner crash (e.g., GitHub Actions terminating abruptly) will prevent Terraform from deleting the `.tflock` object.

**Symptom:** `Error acquiring the state lock... Lock Info: ID: 1234-5678...`

**Resolution (Break the Lock):**
1. Copy the Lock ID from the error message.
2. Authenticate locally with the AWS CLI.
3. Run the force-unlock command:
   ```bash
   terragrunt force-unlock <LOCK_ID>
   ```
*(Note: Only execute this if you are 100% certain the pipeline runner has been terminated and no other process is actively mutating the state).*

## 4. State Corruption & Disasters

If the state file becomes corrupted (highly unlikely due to Terraform's atomic writes, but possible in extreme edge cases):

1. **S3 Versioning:** Our S3 state buckets have **versioning strictly enabled**.
2. **Recovery:**
   - Navigate to the S3 bucket in the AWS Console.
   - Find the specific `.tfstate` file.
   - Delete the current corrupted version to immediately restore the previous known-good version.
3. **Manual Reconciliation:** If resources were created *after* the restored version, you must use `terragrunt import` to bring them back into the state file to prevent Terraform from trying to recreate them.

## 5. Manual State Manipulation (Surgical Strikes)

Sometimes, AWS resources get stuck in a "deleting" state, or someone manually deletes a resource via the console (causing drift). If Terraform is blocked:

**Remove the resource from state:**
```bash
terragrunt state rm module.eks.aws_eks_cluster.this[0]
```
This tells Terraform to "forget" about the resource. The next `apply` will attempt to create it from scratch.

## 6. Loss of the primary region's state bucket (PLAN 7.2)

Each account has one state bucket per region (`tg-state-<account>-<region>`, made by the Day-0 stack). When
`secondary_region` is set on the StackSets module (and `ReplicaRegion` on the management stack), the primary
bucket copies every state file, one way, to the secondary region's bucket. Deletes are **not** copied.

**Recovery, if `tg-state-<account>-eu-central-1` is gone or unusable:**
1. Check the replica first: `aws s3 ls s3://tg-state-<account>-eu-west-1/<state key>` (keys keep the same path,
   for example `workloads/prod/workloads-prod/eu-central-1/network/vpc/terraform.tfstate`).
2. Recreate the primary bucket by re-deploying the Day-0 stack in `eu-central-1` (it is `Retain`, so if only
   the bucket was deleted, the stack update recreates it).
3. Copy the state files back: `aws s3 sync s3://tg-state-<account>-eu-west-1/ s3://tg-state-<account>-eu-central-1/ --exclude "eu-west-1/*"`.
   (The secondary's own leaves keep their state in that bucket under `.../eu-west-1/...`, so leave those alone.)
4. Run `terragrunt plan` on one unit. **An empty plan means the state is current.** A plan that wants to create
   things that exist means the copy was behind (replication is asynchronous, usually seconds): import those
   resources (section 4, step 3).
5. Record the recovery time and the number of imports in `docs/runbooks/` as a postmortem.

If **both** buckets are lost, the infrastructure still exists but Terraform has forgotten it. Recovery is a full
`terragrunt import` per unit and can take days. This is the reason for the replica, the versioning and the
noncurrent-version retention (90 days).

## 7. Regional failover (PLAN 7.1, 7.3, 7.4)

The secondary region (`eu-west-1`) is **warm standby**: the VPC and the EKS control plane exist, the node group
is at zero, and data is replicated. Nothing fails over the compute by itself.

**Decision point:** declare a regional failover only when the primary region is confirmed unavailable and the
incident lead has agreed (a health check alarm alone is not enough).

1. **Data first.** Aurora Global Database: promote the secondary. Unplanned loss:
   `aws rds remove-from-global-cluster --global-cluster-identifier <id> --db-cluster-identifier <secondary arn>`
   (the secondary becomes a standalone writer). Planned switch: `aws rds failover-global-cluster`.
   S3: the replica bucket is already readable. AWS Backup: restore from the copy in the secondary vault.
2. **Compute.** Raise `min_size` / `desired_size` in `workloads-prod/eu-west-1/compute/eks/terragrunt.hcl`,
   merge the PR and let the pipeline apply it (a human approves the prod Environment). Deploy workloads.
3. **Traffic.** `network/route53-failover` moves DNS by itself once the primary health check fails (about 90 s
   plus caching). If it has not, or the alarm was a false positive, do it by hand from the Route 53 console.
4. **Afterwards.** Do not "fail back" the same day. Rebuild the old primary as a *secondary* of the new writer,
   then plan a switch in a quiet window. Update Terraform (`mode`, `global_cluster_identifier`) to match reality.

**Not covered yet:** IAM Identity Center is single-region (the home region), and the organization's central
log-archive and security-tooling accounts run in the primary region only. During a primary-region outage,
sign-in through Identity Center and central logging may be degraded. Use the `BreakGlassAdmin` path
(`docs/IDENTITY.md`).

## 8. RTO and RPO per tier

These are **targets** for design and for the game day. **None has been measured yet**; the first game day
fills the "measured" column.

| Tier | Examples | RPO target | RTO target | How it is met | Measured |
|---|---|---|---|---|---|
| 0 Foundation | Organizations, SCPs, Identity Center, state buckets | 0 (it is code) | 4 h | Git is the source of truth; state replica; Day-0 stack re-deploy | not yet |
| 1 Data, critical | Aurora Global Database | ~1 s (typical replication lag) | 15 min | Cross-region replica, promoted by a human | not yet |
| 1 Data, objects | S3 with replication | minutes (asynchronous) | 15 min | Replica bucket | not yet |
| 2 Compute | Prod EKS, workloads | 0 (stateless) | 60 min | Warm-standby cluster, scale up by PR, redeploy | not yet |
| 3 Edge / DNS | Route 53 failover | n/a | ~3 min | Health check (90 s) + caching | not yet |
| 4 Backups | AWS Backup copies | 24 h (daily plan) | 4 h | Restore from the secondary vault | not yet |
| Non-prod | dev / sandbox | 24 h | best effort | Rebuild from code | not required |

## 9. Quarterly game day (ISO 27001 A.5.29, A.5.30; SOC 2 A1.2, A1.3)

Run it once a quarter in the sandbox, not in prod. Write each run up as a dated file under
`docs/runbooks/gameday-<yyyy-mm>.md`. **That file is the audit evidence.** A test that was not written down did
not happen.

- [ ] **Scope agreed** in advance: which scenario (lose the primary state bucket, lose the primary region, restore
  a backup), who is incident lead, who observes, start and stop time.
- [ ] **Prerequisites checked:** replication is on and lag is small; the secondary vault has recent recovery
  points; the secondary EKS control plane is healthy; the break-glass credentials work (`docs/IDENTITY.md`).
- [ ] **Scenario A, state:** delete (or block access to) a *copy* of a state bucket in the sandbox and recover it
  with section 6. Record: time to a clean plan, imports needed.
- [ ] **Scenario B, region:** simulate the primary being down (fail the health check on purpose) and run
  section 7. Record: time to detect, to promote data, to serve traffic from the secondary.
- [ ] **Scenario C, backup:** restore one recovery point from the secondary vault and check the data.
- [ ] **Measured RTO / RPO** written into the table in section 8.
- [ ] **What went wrong** listed blamelessly, each with an owner and a due date.
- [ ] **Runbook and this file updated** with what the test taught.
- [ ] **Sign-off** by the owner and the date, kept with the record.

---

> **Summary:** Trust the declarative engine. Protect the state. Fix the code. **Roll-Forward.**
