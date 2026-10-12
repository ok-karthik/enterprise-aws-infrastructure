# ADR 0001: Repository topology and the `-repo` convention

> **DRAFT written by an AI model. Owner: rewrite this in your own words before you rely on it in an
> interview (PLAN.md Phase 10: the ADRs are yours). Check every claim; delete this note when done.**

- Status: draft (the two live repos below were merged into `iac-live-repo/` on 2026-10-11, see the last section)
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

## 2026-10-11 revision: one live repo

> DRAFT by the model: the owner rewrites this in his own words.

- **What changed:** `foundation-live-repo/` and `workloads-live-repo/` are merged into one live repo, `iac-live-repo/`
  (`<account>/<region or _global>/<stack>/terragrunt.hcl`, one `root.hcl`, one `_config/` registry, one `_bootstrap/`).
  The helper scripts moved to the repo-root `scripts/`. The table above is the original decision; for the live repos it is
  replaced by this section.
- **Why:** two live repos meant two identical `root.hcl` copies, the registry read across repos, and every change that touches
  both landing zone and workloads needed two PRs. The split by approver never needed a second repository, only a second owner.
- **Where isolation between accounts comes from now:** not from repo boundaries. It comes from per-account CI roles (OIDC,
  `github-actions-plan` read-only and `github-actions-apply` only from that account's GitHub Environment), per-account
  state buckets (`tg-state-<account-id>-<region>`), and GitHub Environments with approvals.
- **Ownership:** CODEOWNERS per OU folder (`/iac-live-repo/<ou>/`, e.g. `/iac-live-repo/root/`, `/iac-live-repo/security/`, `/iac-live-repo/workloads/`); see `.github/CODEOWNERS` and Revision 2026-10-12 below.
- **Unchanged:** `iac-modules-repo` and `policy-library-repo` stay separately versioned (release tags per module; the policy
  bundle is pulled by every pipeline).
- **What we give up:** one repo's history for both teams, and per-repo branch protection and access control (a token for the
  repo reaches every account folder; the account roles are what limits damage).
- **When to split again:** separate teams with separate release cadences, or an audit need for repo-level separation.

## Revision 2026-10-12 (DRAFT by the model; owner to rewrite)

- **What changed:** the folders under `iac-live-repo/` mirror the AWS Organizations OU tree for people:
  `iac-live-repo/<ou path>/<account>/<region or _global>/<stack>/terragrunt.hcl` (for example `root/management`,
  `security/log-archive`, `workloads/nonprod/workloads-dev`).
- **State keys are unchanged:** they are `<account>/<region>/<stack>` (and so is the `Service` tag), because `root.hcl` uses
  only the last three folders. A reorganisation is a folder move plus one registry line, not a state migration.
- **One source for the OU tree:** `iac-live-repo/_config/organization.hcl` (`organizational_units`). The organization stack
  creates the OUs from it, and the scripts derive the folder names from it. `scripts/check-account-registry.sh` checks that an
  account folder is at the folder of its registry OU, and `make org-tree` prints the tree.
- **Ownership:** CODEOWNERS has one line per OU folder.
