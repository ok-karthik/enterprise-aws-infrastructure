# Contributing

This is how to change this repository without surprising anyone. It is written for a new teammate and for an agent:
the review checklist at the end is the same one the Policy Auditor agent uses (`iac-agents-repo/prompts/auditor.md`).

**Ground rules (from [PLAN.md](PLAN.md)):** nobody runs `apply` from a laptop or an agent; a human approves prod;
one focused change per PR; conventional commits with the module name as the scope (`feat(vpc): ...`), because
release-please builds per-module versions from them; and docs change in the same PR as the behaviour.

## Set up (5 minutes)

```bash
make install     # pre-commit hook: fmt + Checkov, the same as CI
make test        # module, policy and script tests, no AWS credentials
make checkov     # the same Checkov result as CI
```

Terraform and Terragrunt versions are in the README badges. Use a per-machine plugin cache
(`TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache`) so `init` does not re-download the AWS provider for every module.

## Add a module in 30 minutes

A module is generic Terraform under `iac-modules-repo/<category>/<name>/`. It knows nothing about accounts, regions or
environments, and it never contains a `provider` or `backend` block (`root.hcl` generates them).

1. **Copy the shape of a small module** such as `iac-modules-repo/network/route53-failover`: `versions.tf`, `variables.tf`,
   `main.tf`, `outputs.tf`, `README.md`, `tests/<name>.tftest.hcl`.
2. **Variables need a `description` and a `validation` where a wrong value is easy to type** (an account ID, an ARN, a name).
   Fail closed: the safe setting is the default, and a risky one needs an explicit value.
3. **Write the test first.** `mock_provider "aws" {}` and `command = plan`. Assert the guardrails (encryption on, public access
   blocked, no `0.0.0.0/0`) and use `expect_failures = [var.x]` for every validation. Run it with
   `cd iac-modules-repo/<category>/<name> && terraform init -backend=false && terraform test`.
4. **Run the gates locally:** `terraform fmt`, `terraform validate`, `make checkov`, `make test`.
   If Checkov flags something the module cannot fix, add `#checkov:skip=<ID>: <reason>` **on that resource** with the real
   reason. A skip without a reason is refused in review. Do not touch `.checkov.yaml`.
5. **Register it:** an entry in `release-please-config.json` and `.release-please-manifest.json` (start at `1.0.0`) and a line
   in the `docs` target of the `Makefile`.
6. **Wire it into a live folder** (a separate commit): an `_envcommon/<category>/<name>.hcl` that sets the module source and
   defaults, and a leaf `<account>/<region>/<category>/<name>/terragrunt.hcl` of about 10 lines. Check it with
   `IAC_MODULES_LOCAL=1 terragrunt render --format json`.
7. **Write the README:** what it makes, the two or three things that are not obvious, and what is *not* covered.

## What a good PR looks like

- **Title** in conventional-commit form: `feat(route53-failover): add DNS failover module (PLAN 7.4)`.
- **Description** answers: what changed, why, how it was checked (commands and results, not "tested"), what was *not*
  checked, and what the owner still has to do before it can be applied.
- **One concern.** A module and the live leaf that uses it can share a PR; a module and an unrelated pipeline change cannot.
- **Small commits with a message that explains why**, not what.
- **Tests that fail without the change.** A test that cannot fail is decoration.
- **The plan and the log updated:** tick the task in `PLAN.md` and add a dated entry to `docs/EXECUTION_LOG.md`, including
  anything skipped or that did not pass. Honest is better than green.
- **No surprises in the plan output.** The PR comment shows what will change and what it costs: read it.

## Who reviews what

CODEOWNERS decides. Changes to `.checkov.yaml`, `policy-library-repo/` and the workflows need a human owner: they define
what "passing" means, so an author (or an agent) never edits them just to make a check go away.

## Review checklist (also used by the Policy Auditor)

Blocking. Any "no" is a change request.

**Guardrails**
- [ ] Encryption at rest is explicit (not left to defaults) where the service supports it.
- [ ] Nothing is open to `0.0.0.0/0` or `::/0` beyond an intentional public endpoint (HTTPS on a load balancer).
- [ ] No IAM `Action: *` on `Resource: *`; no admin-level managed policy outside the apply and break-glass roles.
- [ ] Public access is blocked on every S3 bucket; versioning and server-side encryption are on.
- [ ] Required tags reach every resource: `Service`, `Environment`, `Project`, `Owner`, `DataClassification` (they come from
      `default_tags` in `root.hcl`; a resource type that ignores them needs explicit tags).
- [ ] No old-generation instance types.

**Structure**
- [ ] The module has no `provider` or `backend` block, and nothing environment-specific.
- [ ] Terraform in this repo never calls the Kubernetes API (no `kubernetes`, `helm` or `kubectl` provider).
- [ ] The state key and `Service` tag depend on the folder layout: the change does not move or rename a live folder without a
      state migration plan.
- [ ] A resource that must be replaced uses `name_prefix` with `create_before_destroy` (or the PR explains why not).

**Change hygiene**
- [ ] Every new variable has a description and a validation where it is easy to get wrong.
- [ ] Every skip (`#checkov:skip`) has a reason and is on the resource, not repo-wide.
- [ ] A test exists for the new behaviour, and the docs, `PLAN.md` and the execution log are updated.
- [ ] The PR says what was **not** checked.
- [ ] No real account IDs, organization IDs or secrets were invented: placeholders are marked `TODO(owner)`.

## What to do when a check fails

1. Read the failing check ID and the line. Fix the code first.
2. If it is a false positive, skip it inline with a reason and say so in the PR.
3. Never turn a gate off, lower a threshold or delete a rule to get green. Ask the owner.
