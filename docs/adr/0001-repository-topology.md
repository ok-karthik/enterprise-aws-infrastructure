# ADR 0001: Repository topology and the `-repo` convention

> **DRAFT written by an AI model. Owner: rewrite this in your own words before you rely on it in an
> interview (PLAN.md Phase 10: the ADRs are yours). Check every claim; delete this note when done.**

- Status: draft
- Date: 2026-09-21

## Context

This repository started as one Terragrunt project: modules, live config, policies and the bootstrap
in a single tree, all for a single AWS account. The target is a multi-account, multi-OU landing zone
with different people approving different kinds of change. A change to the organization or an SCP can
lock every account out, a change to a VPC module affects the platform, and a change to a policy rule
changes what every pipeline may deploy. One tree with one set of approvers does not fit that.

The sibling `internal-developer-platform` repository already uses the convention (its ADR 0010)
that **a directory ending in `-repo` is a separate Git repository in a real company**. It only lives
here as a folder so the whole foundation can be read from one checkout.

## Decision

Split by **who approves a change and how much damage a bad change can do**, not by which tool it uses:

| Folder | Becomes | Holds | Approvers |
|---|---|---|---|
| `iac-modules-repo/` | `<org>/iac-modules` | versioned modules, tagged `<module>-vX.Y.Z` by release-please | platform team |
| `foundation-live-repo/` | `<org>/aws-foundation-live` | landing zone: organization, SCPs, bootstrap StackSets, later identity, logging, security tooling, network hub | security + cloud-infra |
| `workloads-live-repo/` | `<org>/aws-workloads-live` | platform stacks in workload accounts (VPC, EKS, data) | platform team |
| `policy-library-repo/` | `<org>/policy-library` | Rego policies and their tests, used by every IaC pipeline | security |
| `.github/` | `<org>/iac-pipelines` | workflows and actions | platform team |

- **`.github/` stays at the root.** GitHub only runs workflows from `.github/workflows/` in the repository
  root, so it cannot move into one of the folders. It is the one folder that is not renamed.
- **The bootstrap folds into foundation** (`foundation-live-repo/_bootstrap/`). It is the Day-0 layer of the
  landing zone and has the same approvers, so it does not need a repo of its own.
- **Live repos pin modules by tag.** Each account's `env.hcl` has a `module_versions` map and `_envcommon`
  builds the module source from it, so a module change is released first and then promoted dev, then prod,
  one PR each. `IAC_MODULES_LOCAL=1` uses the checkout instead, to test a change before releasing it.
- **Each live repo has its own `root.hcl`**, an identical copy, because separate repositories cannot share a file.
- **State keys do not change.** The key comes from `path_relative_to_include()`, which is relative to the folder
  holding `root.hcl`, and the path below that folder is unchanged. Checked by rendering every leaf before and after.

## What I chose against and what it cost

- **One repository with CODEOWNERS per folder.** Simpler, and it still gives different approvers. Rejected as the
  target because CODEOWNERS cannot give different *access* (who can push, who can see), a leaked token for
  the whole repo reaches everything, and CI runs for every change in every folder. It is a fine start, and it is
  what this checkout still is. Cost of splitting: more repos to keep in step (the duplicated `root.hcl`, versioned
  modules, a policy bundle to pull), and cross-repo changes become several PRs.
- **A repo per environment (dev, prod).** Rejected: environments differ by inputs, not by approvers, and
  copies drift. Environments are folders and account-level `env.hcl` instead.
- **A monorepo tool (Nx, Bazel) to get per-folder pipelines.** Rejected: too heavy for this size and it does not
  solve the access question.
- **Cost of the rename:** tags created before it (`vpc-v1.0.0`, ...) point at the old `infrastructure-modules`
  path, so every module has to be released again before the pins can be used. Until then CI runs with
  `IAC_MODULES_LOCAL=1`.

## Consequences

- Extract a folder into its own repository with `git subtree split -P <folder> -b <name>`; each folder has a
  CODEOWNERS header that says so.
- The `internal-developer-platform` catalog must point at `//iac-modules-repo` and at tags that exist at the new
  path (PLAN 1.7, a separate PR in that repository, after the modules are re-released).
