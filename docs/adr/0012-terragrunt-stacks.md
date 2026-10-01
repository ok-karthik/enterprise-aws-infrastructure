# ADR 0012: Terragrunt Stacks — not adopted yet

- Status: draft
- Date: 2026-09-29

## Context

Terragrunt Stacks (`terragrunt.stack.hcl`) let one file describe a group of units (`unit` blocks with a `source`,
a `path` and `values`) and generate the leaf folders from it (`terragrunt stack generate`). The hope in PLAN 8.1 was
to cut the boilerplate in the leaf folders, for `account-baseline` and for the standard workload stack (vpc + eks +
discovery).

I tried it offline with Terragrunt 1.1.1 in a scratch folder (two units, one depending on the other through a
`values` path). It works without AWS access: `terragrunt stack generate` writes each unit to
`.terragrunt-stack/<path>/` with a `terragrunt.hcl` and a `terragrunt.values.hcl`.

What the repo looks like today: 38 `terragrunt.hcl` leaves in total. The duplication a stack would remove is small:
`workloads-prod` has 8 leaves (6 in eu-central-1, and the vpc and eks again in eu-west-1), `workloads-dev` has 6,
and each leaf is a 10-line file that includes `root.hcl` and one `_envcommon`
file and sets a few inputs. The real logic already lives once, in `_envcommon`.

## Decision

**Do not adopt stacks now. Revisit when one of these is true:** more than about 30 leaves per account or a
stamped-out account (vending) needs the same 10 leaves every time, or an environment must be created and
destroyed as one unit (ephemeral preview environments).

## Why not now

1. **State keys and tags would change.** `root.hcl` builds the state key and the `Service` tag from
   `path_relative_to_include()`. A stack generates into `.terragrunt-stack/...`, so that segment would appear in
   every state key and tag, or `root.hcl` has to strip it. Either way it is a state migration (PLAN 2.2 was a
   whole task for the last one), on stacks that are not yet applied but will be.
2. **The layout is a contract.** CI, the account matrix, drift detection (8.7), the smoke test, the agent and the
   `region.hcl` / `account.hcl` lookups all read real folders `<account>/<region>/<category>/<module>`. Generated,
   git-ignored folders break "the folder is the thing you review in a PR".
3. **Review gets harder.** A reviewer sees a stack file and has to know what it expands to. Today the leaf is
   the diff.
4. **Small win.** `_envcommon` already removed the boilerplate that mattered. What is left per leaf is the
   inputs, which are the environment-specific part and should stay visible.

## What I chose against and what it costs

- **Adopting stacks for the standard workload stack:** saves about 3 leaf files per region per workload account.
  Costs: a state-key decision, a CI matrix change and a new concept for every contributor.
- **Adopting them only for `account-baseline`:** one unit per account, so no saving.
- **Cost of waiting:** adding the next region or account is copy-and-edit of about 8 folders (as in Phase 7.1).
  That is tolerable at the current size. A generator (`generate-module.sh`, already there) covers one leaf at a
  time.

## Follow-up

- If revisited, prototype with `values` for the region and CIDR only, keep the generated folder **committed**
  (`terragrunt stack generate` in CI and a diff check) so the review and state-key story stay the same.
