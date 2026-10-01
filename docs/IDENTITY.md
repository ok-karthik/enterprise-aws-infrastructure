# Identity, Access Management, and Privileged Access

Humans never get IAM users or long-lived keys. They sign in through **IAM Identity Center** with an external Identity Provider (Okta, Entra ID, or Google Workspace) and get a short-lived session in each account through a **permission set**.

This document covers human identity architecture, break-glass and just-in-time access, and centralized root access management.

---

## 1. Human Identity: IAM Identity Center with an External IdP

### What is automated and what is by hand

| By hand (this document) | By Terraform (`identity/identity-center`) |
|---|---|
| Enable IAM Identity Center; connect the IdP; turn on SCIM; create the IdP groups | Permission-set catalog, ABAC attributes, group lookups, account assignments |

Identity Center exists once per organization and region and is enabled in the **management account** (or delegated to another account later). Enabling it is a console step; Terraform never creates the instance.

### Setup, step by step

1. **Enable Identity Center** in the management account, in your home region (the region the `identity-center` leaf sits in; change the leaf's region folder if it is not `eu-central-1`). Choose *Identity Center directory* for now: you can switch to the external IdP in step 2.
2. **Connect the IdP** (Settings → Identity source → *External identity provider*). Download the AWS SAML metadata, create the AWS IAM Identity Center application in the IdP, upload the IdP's SAML metadata back, and confirm. Changing the identity source does not delete existing groups, but check assignments afterwards.
3. **Enable automatic provisioning (SCIM).** In the same settings page choose *Enable automatic provisioning* and copy the **SCIM endpoint** and the **access token** into the IdP application's provisioning settings. The token expires after 1 year: put a reminder in your calendar, an expired token stops group sync silently.
4. **Create the groups in the IdP** and assign people to them: `developers`, `platform-engineers`, `security-auditors`, `finance` (or your own names). Push them to AWS through SCIM and wait for them to appear under Identity Center → Groups. **The names in `assignments` and `groups` must match the IdP display names exactly**; the plan fails on a missing group, which is what you want.
5. **Map the ABAC attributes.** The catalog uses two session tags, `team` and `cost_center`. In Identity Center → Settings → *Attributes for access control* they are configured by Terraform, but their **source paths depend on your IdP**. The defaults (`${path:enterprise.department}`, `${path:enterprise.costCenter}`) match the SCIM enterprise extension; check that your IdP sends those attributes, or set `abac_attributes` in the leaf. The `team` value must equal the `team` tag you put on EC2 instances (the Developer policy compares them).
6. **Set the group names and assignments** in the leaf, then `terragrunt plan` and read it. The management apply role can manage Identity Center only after `bootstrap.sh` has been re-run with `AllowIdentityCenterAdmin=true` (it does that by default); applying it by hand with your own SSO profile works either way.
7. **Sign in with the CLI** to check it works: `aws configure sso`, then `aws sso login --profile <name>`. Static access keys are not needed anywhere; remove any that exist.

### The permission sets

| Set | Gives | Session |
|---|---|---|
| `ReadOnly` | `ReadOnlyAccess` | 8 h |
| `Developer` | customer-managed policy `platform-developer` + boundary `platform-workload-boundary`; **only NonProd, Sandbox, Policy-Staging** (ReadOnly in Prod). EC2 start/stop/launch is limited by the `team` tag | 8 h |
| `PlatformEngineer` | `PowerUserAccess` + IAM only on `role/platform/*` and only for roles that carry the workload boundary; cannot attach admin policies | 1 h |
| `SecurityAudit` | `SecurityAudit` + `ViewOnlyAccess` | 8 h |
| `Billing` | `Billing` | 8 h |
| `BreakGlassAdmin` | `AdministratorAccess` | 1 h |

Rules the module enforces (a wrong assignment fails at plan time, not in production):

- `BreakGlassAdmin` is **never** assigned statically; it is granted just in time (see below).
- `PlatformEngineer` and `BreakGlassAdmin` cannot be assigned statically in **Prod** (`jit_only_ous`); engineers get them just in time.
- `Developer` is refused outside NonProd, Sandbox and Policy-Staging.
- Only accounts with a real account id are assigned; registry placeholders are skipped.

### Adding a person, a team or an account

- **A person:** add them to the IdP group. Nothing in this repo changes.
- **A new group:** create it in the IdP, add its name to `groups` and to `assignments` in the leaf.
- **A new account:** it is picked up from the registry (`foundation-live-repo/_config/accounts.hcl`) once it has a real id and `create = true`; its OU decides what it gets. The `platform-developer` policy and the boundary come from the account baseline, so apply that first, or the Developer assignment fails.

### Gotchas

- SCIM-synced groups and users are read-only in AWS: change them in the IdP. Terraform only reads groups (`manage_groups = false`).
- A permission-set change re-provisions the role in every assigned account; large fan-outs can take minutes.
- The management account is not covered by SCPs, so its assignments matter more than any others: keep it to `ReadOnly` and `Billing`.

---

## 2. Break-Glass and Just-in-Time (JIT) Access

**Nobody has standing administrator access.** Two privileges are granted only for a limited time, after an approval, with an immutable audit record:

- `BreakGlassAdmin` (`AdministratorAccess`, 1-hour sessions): for emergencies, in any account.
- `PlatformEngineer` **in Prod** (PowerUser plus IAM on `role/platform/*`): for planned production work.

Everything else is assigned statically through groups.

### What this repository enforces

| Rule | Where |
|---|---|
| `BreakGlassAdmin` is never assigned statically | `identity/identity-center` refuses it at plan time (`allow_static_break_glass` is a deliberate exception) |
| `PlatformEngineer` / `BreakGlassAdmin` cannot be assigned statically in Prod | same module, `jit_only_ous` |
| 1-hour sessions for the elevated sets | permission-set session duration |
| Every sign-in as `BreakGlassAdmin` sends an email | `security/break-glass-alerts`, applied in every account |

What this repository does **not** contain is the JIT tool itself. That is a product you deploy and configure (below). Assignments it creates are separate from Terraform's: the `identity-center` module only manages the assignments it created, so JIT grants do not show up as drift.

### The JIT tool: AWS TEAM (or an equivalent)

Use **AWS TEAM** (Temporary Elevated Access Management, the open-source AWS sample built on IAM Identity Center) or a SaaS access-request product. Whatever you pick must do four things:

1. **Request:** a person asks for a permission set in an account, for a duration, with a reason (a ticket number).
2. **Approve:** a *different* person approves. Nobody approves their own request.
3. **Time-limit:** it creates the Identity Center assignment and removes it when the time is up.
4. **Log:** who asked, who approved, why, for how long. The record is kept where the requester cannot change it (the `log-archive` account).

#### Setup checklist

- [ ] Deploy the tool in the **management account**, or in a **delegated Identity Center administrator** account (cleaner: it keeps the tool away from the payer account). Identity Center is where assignments are created, so it has to be allowed to manage them.
- [ ] Create three IdP groups (SCIM-synced): `jit-requesters` (the platform engineers), `jit-approvers`, `jit-auditors` (read the log).
- [ ] Configure the **eligibility** rules:

  | Permission set | Accounts | Who may request | Approval | Maximum duration |
  |---|---|---|---|---|
  | `BreakGlassAdmin` | all | `jit-requesters` | required, by someone else, ticket required | 2 hours |
  | `PlatformEngineer` | Prod accounts | `jit-requesters` | required, ticket required | 4 hours |

- [ ] Send the tool's audit log to `log-archive` (Object Lock) and keep it 400 days (SOC2 CC6.2, CC6.3; ISO 27001 A.8.2).
- [ ] Apply `security/break-glass-alerts` in every account and **confirm the SNS subscription** in each mailbox.
- [ ] Run the drill below once before you rely on any of this.

### Runbook: using break-glass

**When:** a production outage or a security incident that the normal permission sets cannot fix. Not for convenience: use `PlatformEngineer` with an approved request for planned work.

1. **Open an incident or ticket** and announce in the incident channel that break-glass is being requested and why.
2. **Request** `BreakGlassAdmin` for the affected account(s) in the JIT tool, with the ticket number and the shortest duration that will do.
3. **Get it approved** by an approver who is not you. The approver checks the ticket, not just the request.
4. **Sign in** (`aws sso login --profile <name>` or the portal). The alert email fires: that is expected, and the on-call and security mailboxes should recognise it.
5. **Work in small, recorded steps.** Prefer a change you can describe in the ticket. If you change infrastructure by hand, write it down: it becomes drift, and it has to go back into code.
6. **Stop when it is fixed.** Let the session expire or end the request early in the tool. Do not extend "just in case".
7. **Afterwards (within 2 working days):** put the manual changes into Terraform, close the ticket with the timeline, and review the alert emails against the approved requests. Every alert has a request; every request had an alert.

### If an alert arrives and nobody asked for it

Treat it as a **security incident**:

1. Remove the assignment (the JIT tool, or Identity Center → the account → the permission set → remove) and sign the user out (revoke active sessions in the IdP).
2. Ask the person named in the alert. If they did not do it, escalate: rotate their IdP credentials and check what the session did (CloudTrail, filter by the session role).
3. Write a short blameless postmortem.

### If the JIT tool is down

- **A second person creates a time-limited assignment by hand** in Identity Center (management account, someone with `PlatformEngineer` in the account holding Identity Center), for at most 1 hour, with the ticket in the description. **Remove it when the time is up.** The alert still fires, and the manual grant is written into the ticket.
- Fix the tool afterwards. A manual path that stays in use is a standing path.

### If the IdP (or Identity Center) is down

There is no single sign-on, so the last resort is the **root user of the management account**: a hardware MFA key kept offline, opened by two people, and used only to restore access. Member accounts have no root credentials (centralized root access management): from the management account use `sts:AssumeRoot` for a privileged task (see below). Any root sign-in is an incident by definition; afterwards rotate the MFA registration and review CloudTrail.

### Drill plan: break-glass verification

1. Have someone request and get `BreakGlassAdmin` approved in a sandbox account.
2. Sign in by console and by CLI. Check that **each** path produced an email via `security/break-glass-alerts`.
3. Check that the assignment disappeared at the end and that the request is in the audit log.
4. Document the results and actual latency.

---

## 3. Centralized Root Access Management

**Member accounts do not need root credentials.** With centralized root access management (`enable_centralized_root_access` in the `governance/organization` module: `RootCredentialsManagement` and `RootSessions`), the root user's password, access keys, signing certificates and MFA can be **removed** from every member account, and the few tasks that only the root user can do are done from the management account with a short-lived, single-purpose root session.

The **management account's own root user** is different: it keeps its credentials (a hardware MFA key kept offline, two-person rule). Centralized root access only covers member accounts.

### One-off: remove the root credentials from a member account

For each member account, from the management account (using a break-glass session):

1. **Audit** what root credentials exist: assume the `IAMAuditRootUserCredentials` root task, then list the root user's credentials.
2. **Delete** them with the `IAMDeleteRootUserCredentials` task: the password, any access keys, signing certificates and MFA devices.
3. Record it in the account's ticket. Accounts created *after* the feature is on come without root credentials; check one to confirm.

### Doing a privileged root task

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

### Rules

- **Break-glass only.** `sts:AssumeRoot` is an administrator-level action: it is not part of `PlatformEngineer` and is reached through a just-in-time `BreakGlassAdmin` request with a ticket. Every use is an alert and is reviewed afterwards.
- **Never re-create root credentials** in a member account to "have them ready". The point is that they do not exist.
- **The management account root** is used only when the identity provider or Identity Center is down; any root sign-in is an incident by definition.

### What the code does and does not do

- `governance/organization` enables the two features (needs trusted access for `iam.amazonaws.com`, which the default list includes; the module refuses to plan without it). Applied by the owner from the management account.
- It does **not** delete the existing root credentials: that is the one-off procedure above.
- The apply role's permissions boundary does not touch this: the organization stack is applied by the owner, not by CI.
