# Root access in member accounts (centralized root access management)

**Member accounts do not need root credentials.** With centralized root access management (`enable_centralized_root_access` in the `governance/organization` module: `RootCredentialsManagement` and `RootSessions`), the root user's password, access keys, signing certificates and MFA can be **removed** from every member account, and the few tasks that only the root user can do are done from the management account with a short-lived, single-purpose root session.

The **management account's own root user** is different: it keeps its credentials (a hardware MFA key kept offline, two-person rule, see [BREAK_GLASS.md](BREAK_GLASS.md)). Centralized root access only covers member accounts.

> I could not check the current AWS documentation from this repository. The task-policy names and the CLI call below are the ones I know; confirm them against the AWS docs for `sts:AssumeRoot` before relying on them.

## One-off: remove the root credentials from a member account

For each member account, from the management account (use a break-glass session; see [BREAK_GLASS.md](BREAK_GLASS.md)):

1. **Audit** what root credentials exist: assume the `IAMAuditRootUserCredentials` root task, then list the root user's credentials.
2. **Delete** them with the `IAMDeleteRootUserCredentials` task: the password, any access keys, signing certificates and MFA devices.
3. Record it in the account's ticket. Accounts created *after* the feature is on should come without root credentials; check one, do not assume.

## Doing a privileged root task

Only a few actions still need root. Assume a root session in the **target member account**, scoped to one task policy:

| Task policy | Use it to |
|---|---|
| `IAMAuditRootUserCredentials` | see which root credentials exist |
| `IAMDeleteRootUserCredentials` | delete them |
| `IAMCreateRootUserPassword` | set a root password, when you must recover the root user (last resort) |
| `S3UnlockBucketPolicy` | remove a bucket policy that locks everyone out, including administrators |
| `SQSUnlockQueuePolicy` | remove a queue policy that locks everyone out |

```bash
# From the management account, with a break-glass session (BreakGlassAdmin):
aws sts assume-root \
  --target-principal <member-account-id> \
  --task-policy-arn arn=arn:aws:iam::aws:policy/root-task/S3UnlockBucketPolicy \
  --duration-seconds 900
```

The result is temporary credentials (15 minutes) that can do that one thing. Use them, then let them expire.

## Rules

- **Break-glass only.** `sts:AssumeRoot` is an administrator-level action: it is not part of `PlatformEngineer` and is reached through a just-in-time `BreakGlassAdmin` request with a ticket. Every use is an alert and is reviewed afterwards.
- **Never re-create root credentials** in a member account to "have them ready". The point is that they do not exist.
- **The management account root** is used only when the identity provider or Identity Center is down ([BREAK_GLASS.md](BREAK_GLASS.md)); any root sign-in is an incident by definition. Alerting on root sign-in comes with PLAN 4.5.

## What the code does and does not do

- `governance/organization` enables the two features (needs trusted access for `iam.amazonaws.com`, which the default list includes; the module refuses to plan without it). Applied by the owner from the management account.
- It does **not** delete the existing root credentials: that is the one-off procedure above.
- The apply role's permissions boundary does not touch this: the organization stack is applied by the owner, not by CI.
