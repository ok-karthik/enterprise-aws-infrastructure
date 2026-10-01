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
| encryption-ec2 | Unencrypted root or extra block devices on `aws_instance`, and launch template EBS mappings without `encrypted = true` | `require_encryption.rego` | high | No Checkov equivalent: `CKV_AWS_8` (instances) is skipped repo-wide in `.checkov.yaml`, and Checkov has no launch template check |
| open-datastore-ports | Security group ingress from `0.0.0.0/0` or `::/0` on 5432, 3306, 6379, 27017, 9200 (or all ports) | `deny_open_ingress.rego` | critical | Checkov only covers 22, 3389, 80 and all ports (`CKV_AWS_24`, `25`, `260`, `277`), not datastore ports |
| iam-wildcards | IAM policy that allows `Action: *` on `Resource: *` (permissions boundaries are named exceptions) | `deny_iam_wildcards.rego` | critical | Organisational permission boundary (`platform-workload-boundary`) is a named exception |

## Moved to Checkov (PLAN 8.10)

These used to be Rego rules. Each case was mapped to a Checkov check (IDs confirmed with `checkov --list`) and the Rego
was removed or trimmed. Checkov enforces them on the HCL and on every `tfplan.json`.

| Was | Now enforced by |
|---|---|
| `deny_public_s3.rego` (block public access flags, public bucket policy), removed | `CKV_AWS_53`, `54`, `55`, `56`, `CKV_AWS_70` |
| `require_encryption.rego`: RDS, standalone EBS volumes, S3, SQS, SNS, trimmed | `CKV_AWS_16`, `CKV_AWS_3`, `CKV_AWS_19`, `CKV_AWS_27`, `CKV_AWS_26` |
| `deny_open_ingress.rego`: ports 22 and 3389, trimmed | `CKV_AWS_24`, `CKV_AWS_25` |

Not fully equivalent, worth knowing: Rego accepted a bucket policy with `Principal: "*"` when limited by
`aws:PrincipalOrgID`; check `CKV_AWS_70`'s behaviour on that pattern before relying on it. The old "S3 SSE must be in
the same module" logic is replaced by `CKV_AWS_19`, which checks the bucket's own encryption configuration resource.

`helpers.rego` holds shared functions, not rules.


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
