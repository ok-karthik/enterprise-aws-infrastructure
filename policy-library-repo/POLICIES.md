# Enforced policies (PLAN 8.10)

One catalog of every rule that can fail a PR. **CI fails if a `.rego` file in `policy-library-repo/terraform/` is
not listed here** (`workloads-live-repo/scripts/check_policy_catalog.py`).

## Which tool owns a rule

- If Checkov has a built-in check for it, **Checkov** owns it (settings only in `.checkov.yaml`).
- **Rego** is only for rules about *this* organisation: tag keys, role names, account and OU rules, allowed modules.
- A PR that adds a Rego rule must say in its description why Checkov cannot do it.
- Each tool answers one question: tflint = is it written correctly, Checkov = is it secure, Rego = does it follow
  this org's rules, Trivy = is the toolbox image free of known CVEs.

## Rego rules

| ID | What it blocks | File | Severity | Why Rego, not Checkov |
|---|---|---|---|---|
| tags | A created or updated resource missing `Service`, `Environment`, `Project`, `Owner` or `DataClassification` in `tags_all` | `require_tags.rego` | high | Org-specific tag keys |
| admin-attachments | Admin-level managed policies on anything except `github-actions-apply*` / `break-glass*` roles or the break-glass permission set | `deny_admin_attachments.rego` | critical | Org-specific role names |
| member-org-admin | A member-account bootstrap StackSet that can manage Organizations or Identity Center, or is not named `bootstrap-*` | `deny_member_org_admin.rego` | critical | Org-specific StackSet contract |
| legacy-instances | Old-generation EC2 instance types | `no_legacy_instances.rego` | medium | Org-specific list of allowed families |
| public-s3 | Missing S3 Block Public Access flags; bucket policy with `Principal: "*"` and no `aws:PrincipalOrgID` | `deny_public_s3.rego` | critical | **Overlaps Checkov** (CKV_AWS_53-56, CKV_AWS_70). Kept until each test case is mapped to a Checkov ID (8.10) |
| encryption | Unencrypted RDS, EBS, launch template volumes, S3 without SSE config, SQS and SNS | `require_encryption.rego` | high | **Overlaps Checkov** (CKV_AWS_16, 3, 19, 27, 26). Same |
| open-ingress | Security group ingress from `0.0.0.0/0` on 22, 3389, 5432, 3306, 6379, 27017, 9200 (or all ports) | `deny_open_ingress.rego` | critical | **Overlaps Checkov** (CKV_AWS_24, 25, 260). Same |
| iam-wildcards | IAM policy that allows `Action: *` on `Resource: *` (permissions boundaries are named exceptions) | `deny_iam_wildcards.rego` | critical | **Overlaps Checkov** (CKV_AWS_62, 63, 286-290). Same |

`helpers.rego` holds shared functions, not rules.

> The Checkov IDs above are a starting guess written from memory and **not yet verified** against Checkov's list.
> Checking them is the first step of the 8.10 mapping.

The four "overlaps Checkov" rules are candidates for removal, **only after** every case in their `_test.rego` maps
to a Checkov check and Checkov is confirmed blocking locally and in CI. Not done yet: see `docs/EXECUTION_LOG.md`.

## Checkov

Every Checkov check that is not skipped is enforced, on the HCL (static) and on every `tfplan.json`. The list of
repo-wide skips, each with its reason, is in `.checkov.yaml`.

## How to request an exception

- **Checkov:** an inline `#checkov:skip=<ID>: <reason>` on the resource that needs it. The reason is required, and
  the reviewer (CODEOWNERS on this path) decides. A repo-wide skip in `.checkov.yaml` needs a comment with its
  reason and the same review.
- **Rego:** today an exception is a named allow-list inside the rule itself (see `deny_iam_wildcards.rego`), with a
  comment saying why. A separate `exceptions` data file is not built yet.
- Only a human edits `.checkov.yaml`, this catalog and `policy-library-repo/`. They decide what "passing" means.
