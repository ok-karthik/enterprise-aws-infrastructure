# Break-glass and just-in-time (JIT) access

**Nobody has standing administrator access.** Two things are granted only for a limited time, after an approval, with a record:

- `BreakGlassAdmin` (`AdministratorAccess`, 1-hour sessions): for emergencies, in any account.
- `PlatformEngineer` **in Prod** (PowerUser plus IAM on `role/platform/*`): for planned production work.

Everything else is assigned statically through groups (see [IDENTITY.md](IDENTITY.md)).

## What this repository enforces

| Rule | Where |
|---|---|
| `BreakGlassAdmin` is never assigned statically | `identity/identity-center` refuses it at plan time (`allow_static_break_glass` is a deliberate exception) |
| `PlatformEngineer` / `BreakGlassAdmin` cannot be assigned statically in Prod | same module, `jit_only_ous` |
| 1-hour sessions for the elevated sets | permission-set session duration |
| Every sign-in as `BreakGlassAdmin` sends an email | `security/break-glass-alerts`, applied in every account |

What this repository does **not** contain is the JIT tool itself. That is a product you deploy and configure (below). Assignments it creates are separate from Terraform's: the `identity-center` module only manages the assignments it created, so JIT grants do not show up as drift.

## The JIT tool: AWS TEAM (or an equivalent)

Use **AWS TEAM** (Temporary Elevated Access Management, the open-source AWS sample built on IAM Identity Center) or a SaaS access-request product. Whatever you pick must do four things:

1. **Request:** a person asks for a permission set in an account, for a duration, with a reason (a ticket number).
2. **Approve:** a *different* person approves. Nobody approves their own request.
3. **Time-limit:** it creates the Identity Center assignment and removes it when the time is up.
4. **Log:** who asked, who approved, why, for how long. The record is kept where the requester cannot change it (the `log-archive` account, PLAN 4.1/4.2).

> I could not check the current AWS TEAM installation guide from this repository, so follow the upstream README for the deployment itself and use the checklist below for the decisions.

### Setup checklist

- [ ] Deploy the tool in the **management account**, or in a **delegated Identity Center administrator** account (cleaner: it keeps the tool away from the payer account). Identity Center is where assignments are created, so it has to be allowed to manage them.
- [ ] Create three IdP groups (SCIM-synced, [IDENTITY.md](IDENTITY.md)): `jit-requesters` (the platform engineers), `jit-approvers`, `jit-auditors` (read the log).
- [ ] Configure the **eligibility** rules:

  | Permission set | Accounts | Who may request | Approval | Maximum duration |
  |---|---|---|---|---|
  | `BreakGlassAdmin` | all | `jit-requesters` | required, by someone else, ticket required | 2 hours |
  | `PlatformEngineer` | Prod accounts | `jit-requesters` | required, ticket required | 4 hours |

- [ ] Send the tool's audit log to `log-archive` (Object Lock, PLAN 4.1) and keep it 400 days (SOC2 CC6.2, CC6.3; ISO 27001 A.8.2).
- [ ] Apply `security/break-glass-alerts` in every account and **confirm the SNS subscription** in each mailbox.
- [ ] Run the drill below once before you rely on any of this.

## Runbook: using break-glass

**When:** a production outage or a security incident that the normal permission sets cannot fix. Not for convenience: use `PlatformEngineer` with an approved request for planned work.

1. **Open an incident or ticket** and announce in the incident channel that break-glass is being requested and why.
2. **Request** `BreakGlassAdmin` for the affected account(s) in the JIT tool, with the ticket number and the shortest duration that will do.
3. **Get it approved** by an approver who is not you. The approver checks the ticket, not just the request.
4. **Sign in** (`aws sso login --profile <name>` or the portal). The alert email fires: that is expected, and the on-call and security mailboxes should recognise it.
5. **Work in small, recorded steps.** Prefer a change you can describe in the ticket. If you change infrastructure by hand, write it down: it becomes drift, and it has to go back into code.
6. **Stop when it is fixed.** Let the session expire or end the request early in the tool. Do not extend "just in case".
7. **Afterwards (within 2 working days):** put the manual changes into Terraform, close the ticket with the timeline, and review the alert emails against the approved requests. Every alert has a request; every request had an alert.

## If an alert arrives and nobody asked for it

Treat it as a **security incident**:

1. Remove the assignment (the JIT tool, or Identity Center → the account → the permission set → remove) and sign the user out (revoke active sessions in the IdP).
2. Ask the person named in the alert. If they did not do it, escalate: rotate their IdP credentials and check what the session did (CloudTrail, filter by the session role).
3. Write a short blameless postmortem.

## If the JIT tool is down

- **A second person creates a time-limited assignment by hand** in Identity Center (management account, someone with `PlatformEngineer` in the account holding Identity Center), for at most 1 hour, with the ticket in the description. **Remove it when the time is up.** The alert still fires, and the manual grant is written into the ticket.
- Fix the tool afterwards. A manual path that stays in use is a standing path.

## If the IdP (or Identity Center) is down

There is no single sign-on, so the last resort is the **root user of the management account**: a hardware MFA key kept offline, opened by two people, and used only to restore access. Member accounts have no root credentials (centralized root access management, PLAN 3.5): from the management account use `sts:AssumeRoot` for a privileged task, see [ROOT_ACCESS.md](ROOT_ACCESS.md). Any root sign-in is an incident by definition (the alerting for it comes with PLAN 4.5); afterwards rotate the MFA registration and review CloudTrail.

## Drill (do this once, then every quarter)

PLAN 10.5: a failure drill with a written postmortem.

1. Have someone request and get `BreakGlassAdmin` approved in a sandbox account.
2. Sign in by console and by CLI. Check that **each** path produced an email. The rules match CloudTrail events by name; if a path stays silent, look at the real event in CloudTrail and correct the pattern in `security/break-glass-alerts` (the Identity Center portal rule is the one to check first: its field names differ between `Federate` and `GetRoleCredentials`).
3. Check that the assignment disappeared at the end and that the request is in the audit log.
4. Write down what surprised you.

## Evidence for an auditor

Access approvals and their log (JIT tool export), the alert emails, the Identity Center assignments (Terraform plus the tool's own), and the drill postmortem. Map them in `docs/COMPLIANCE.md` (PLAN 4.7, not written yet).
