# Runbook: blue-green for infrastructure that cannot change in place (PLAN 8.4)

Some changes cannot be made to a running resource, or would break everything that depends on it while they happen:

- a **VPC CIDR** change (the CIDR of a VPC cannot be edited, and every subnet, route and peering uses it),
- an **EKS major version** upgrade that skips a version or needs new node AMIs and add-ons together,
- a **Transit Gateway** change that replaces the gateway (ASN, or the attachment layout).

For these, do not "edit and apply". Build the new one next to the old one, move traffic over, then remove the old one.

**Nothing here was run against AWS.** The steps are the plan, not a record of a rehearsal. Do the first one in the sandbox and write the timings into a postmortem (PLAN 10.5).

## When to use which approach

| Change | Use |
|---|---|
| Security group, IAM policy, tag, most add-ons | In place. Where the resource supports it, `create_before_destroy` is set (a `name_prefix` gives the replacement a new name). |
| A fixed-name resource that must be replaced | Blue-green (below), because `create_before_destroy` would fail on the duplicate name. |
| VPC CIDR, EKS major version, TGW replacement | Blue-green (below). |

## The pattern, in six steps

1. **Add "green" beside "blue" in code.** A second leaf folder with a different name (for example `network/vpc-v2` or `compute/eks-v2`), never an edit of the existing one. Give it a non-overlapping CIDR (check IPAM, `network/ipam`). Merge it through the normal PR, plan, approval and apply path.
2. **Wire green to the same dependencies** (Transit Gateway attachment, discovery parameters, endpoints), but do **not** publish it as the default yet. The discovery parameters (`/platform/<env>/<region>/...`) have one owner per name, so a second stack needs its own names until cutover.
3. **Prove green in isolation.** Deploy a test workload, resolve DNS, reach the shared endpoints, pass the smoke test. Write down what you checked.
4. **Cut traffic over.** Lowest-risk first:
   - DNS: shift the weight or the failover record in `network/route53-failover` (or a weighted record) from blue to green. A low TTL beforehand shortens the switch.
   - Workloads: redeploy them to green (for EKS, point the GitOps target at the new cluster).
   - Data is not moved by this runbook. If the database lives in the old VPC, plan its move separately (snapshot restore or Aurora Global promotion), and do it before or as part of the cutover.
5. **Watch, then wait.** Keep blue running and idle for a set time (start with 48 hours in prod, less in NonProd). Rolling back is switching traffic back, which is cheap only while blue still exists.
6. **Remove blue.** A PR that deletes the old leaf. Check first that nothing still references it (`terragrunt dag graph` or a search for its outputs and discovery parameter names), and check `deletion_protection` on anything stateful.

## Rollback

Before step 6: switch traffic back to blue (step 4 in reverse). After step 6: blue is gone, so the way back is to rebuild it from code, and any data written to green since the cutover must be carried over. This is why step 5 exists.

## Checklist before you start

- [ ] Change cannot be done in place (write down why).
- [ ] Green has its own CIDR/names and does not touch blue's state.
- [ ] Cost of running both is known (`FINOPS.md`) and the overlap window is time-boxed.
- [ ] A rollback trigger is written down (which metric, which threshold).
- [ ] A second person has read the plan.
- [ ] Owner is available for the prod approval gate at cutover time, not only at merge time.
