# Human identity: IAM Identity Center with an external IdP

Humans never get IAM users or long-lived keys. They sign in through **IAM Identity Center** with your IdP (Okta, Entra ID or Google Workspace) and get a short-lived session in each account through a **permission set**. This document is the manual part; the rest is the `identity/identity-center` module (`foundation-live-repo/management/eu-central-1/identity/identity-center`).

## What is automated and what is by hand

| By hand (this document) | By Terraform (`identity/identity-center`) |
|---|---|
| Enable IAM Identity Center; connect the IdP; turn on SCIM; create the IdP groups | Permission-set catalog, ABAC attributes, group lookups, account assignments |

Identity Center exists once per organization and region and is enabled in the **management account** (or delegated to another account later). Enabling it is a console step; Terraform never creates the instance.

## Setup, step by step

1. **Enable Identity Center** in the management account, in your home region (the region the `identity-center` leaf sits in; change the leaf's region folder if it is not `eu-central-1`). Choose *Identity Center directory* for now: you can switch to the external IdP in step 2.
2. **Connect the IdP** (Settings → Identity source → *External identity provider*). Download the AWS SAML metadata, create the AWS IAM Identity Center application in the IdP, upload the IdP's SAML metadata back, and confirm. Changing the identity source does not delete existing groups, but check assignments afterwards.
3. **Enable automatic provisioning (SCIM).** In the same settings page choose *Enable automatic provisioning* and copy the **SCIM endpoint** and the **access token** into the IdP application's provisioning settings. The token expires after 1 year: put a reminder in your calendar, an expired token stops group sync silently.
4. **Create the groups in the IdP** and assign people to them: `developers`, `platform-engineers`, `security-auditors`, `finance` (or your own names). Push them to AWS through SCIM and wait for them to appear under Identity Center → Groups. **The names in `assignments` and `groups` must match the IdP display names exactly**; the plan fails on a missing group, which is what you want.
5. **Map the ABAC attributes.** The catalog uses two session tags, `team` and `cost_center`. In Identity Center → Settings → *Attributes for access control* they are configured by Terraform, but their **source paths depend on your IdP**. The defaults (`${path:enterprise.department}`, `${path:enterprise.costCenter}`) match the SCIM enterprise extension; check that your IdP sends those attributes, or set `abac_attributes` in the leaf. The `team` value must equal the `team` tag you put on EC2 instances (the Developer policy compares them).
6. **Set the group names and assignments** in the leaf, then `terragrunt plan` and read it. The management apply role can manage Identity Center only after `bootstrap.sh` has been re-run with `AllowIdentityCenterAdmin=true` (it does that by default); applying it by hand with your own SSO profile works either way.
7. **Sign in with the CLI** to check it works: `aws configure sso`, then `aws sso login --profile <name>`. Static access keys are not needed anywhere; remove any that exist.

## The permission sets

| Set | Gives | Session |
|---|---|---|
| `ReadOnly` | `ReadOnlyAccess` | 8 h |
| `Developer` | customer-managed policy `platform-developer` + boundary `platform-workload-boundary`; **only NonProd, Sandbox, Policy-Staging** (ReadOnly in Prod). EC2 start/stop/launch is limited by the `team` tag | 8 h |
| `PlatformEngineer` | `PowerUserAccess` + IAM only on `role/platform/*` and only for roles that carry the workload boundary; cannot attach admin policies | 1 h |
| `SecurityAudit` | `SecurityAudit` + `ViewOnlyAccess` | 8 h |
| `Billing` | `Billing` | 8 h |
| `BreakGlassAdmin` | `AdministratorAccess` | 1 h |

Rules the module enforces (a wrong assignment fails at plan time, not in production):

- `BreakGlassAdmin` is **never** assigned statically; it is granted just in time ([BREAK_GLASS.md](BREAK_GLASS.md)).
- `PlatformEngineer` and `BreakGlassAdmin` cannot be assigned statically in **Prod** (`jit_only_ous`); people get them just in time.
- `Developer` is refused outside NonProd, Sandbox and Policy-Staging.
- Only accounts with a real account id are assigned; registry placeholders are skipped.

## Adding a person, a team or an account

- **A person:** add them to the IdP group. Nothing in this repo changes.
- **A new group:** create it in the IdP, add its name to `groups` and to `assignments` in the leaf.
- **A new account:** it is picked up from the registry (`foundation-live-repo/_config/accounts.hcl`) once it has a real id and `create = true`; its OU decides what it gets. The `platform-developer` policy and the boundary come from the account baseline, so apply that first, or the Developer assignment fails.

## Gotchas

- SCIM-synced groups and users are read-only in AWS: change them in the IdP. Terraform only reads groups (`manage_groups = false`).
- A permission-set change re-provisions the role in every assigned account; large fan-outs can take minutes.
- The management account is not covered by SCPs, so its assignments matter more than any others: keep it to `ReadOnly` and `Billing`.
