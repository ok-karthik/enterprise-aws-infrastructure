# Agent autonomy levels (PLAN 11.4)

How much each agent in this repository is allowed to do, in which environment, and **which control actually enforces it**.
A rule that only says "the agent should not" is not a control. Every cell in the last column names something that exists.

## The levels

| Level | Name | What the agent may do |
|---|---|---|
| **L0** | Explain | Reads and answers. Changes nothing. |
| **L1** | Propose | Produces a diff or a pull request. A human merges. |
| **L2** | Validate | L1, and also runs the checks and fixes its own diff, on its own branch. |
| **L3** | Apply non-prod | Applies to non-production after checks pass. |
| **L4** | Remediate prod | Fixes production on its own. |

**Today every agent is L0, L1 or L2. None is L3 or L4, and none may apply.** No agent code path calls `apply`
(the only `apply` in `iac-agents-repo/` is `git apply`), and no agent workflow assumes an AWS role.

Moving an agent up a level needs three things: its numbers from the weekly delivery metrics (`docs/SLO.md`, PLAN 11.5), an ADR,
and the owner's sign-off. Not a model's opinion.

## One row per agent

Agents are those in [`AGENTS.md`](../../AGENTS.md) and [`iac-agents-repo/README.md`](../README.md), plus the two ways of triggering the generation agent
(drift `/reconcile` and ChatOps `/generate`) and the local coding agents.

| Agent | Level (dev / prod) | What it may do there | The control that enforces it |
|---|---|---|---|
| **IaC Architect** (`prompts/architect.md`) | L1 / L1 | Writes HCL for a human to review. | A prompt, so **no technical control by itself**: it produces text. Its output only reaches the repo through a PR (`.github/CODEOWNERS`, and branch protection once it exists, see gaps). |
| **Policy Auditor** (`prompts/auditor.md`) | L0 / L0 | Reads a diff and answers `STATUS: PASSED` or `FAILED`. | Read-only: it has no tools. Its verdict is advice; the blocking gates are Checkov and Rego in CI (`policy-library-repo/POLICIES.md`). |
| **Pipeline Healer** (`prompts/ci_healer.md`, `ci_healer/healer_runner.py`) | L1 / L1 | Pushes a fix **commit** to the branch of a failed PR run. | `healer_guards.py` (tested): refuses `main`, refuses a branch without an open PR, stops after 3 healer commits, refuses patches that touch protected paths. `pipeline_healer.yml` `permissions:` gives it `contents: write` and `pull-requests: write`, and **no `id-token`, so it cannot assume an AWS role**. |
| **IaC Generation Agent** (`iac_agent/iac_agent.py`) | L2 / L1 | Generates a diff and runs the validation ladder (offline init, tflint, conftest, checkov, Infracost) on its own branch. **Prod: proposals only.** | `check_sre_error_budget()` freezes prod proposals when the measured error budget is below 10% (`sre/error_budgets.yaml`, `docs/SLO.md`). The plan step needs the read-only `github-actions-plan` role. Nothing in it applies. |
| **Drift `/reconcile`** (issue comment on a drift issue, `chatops_generator.yml`) | L1 / L1 | Turns the drift plan in the issue into a PR. | `chatops_generator.yml`: only `OWNER`, `MEMBER`, `COLLABORATOR` comments run it; `permissions:` has no `id-token`; the agent runs with `--skip-plan` (no AWS access at all); the PR gets the `ai-generated` label. |
| **ChatOps `/generate`** (`chatops_generator.yml`) | L1 / L1 | Creates a branch and opens a PR from a comment. | Same as above. A human still reviews and merges. |
| **Local coding agents** (Claude Code and others, rules in `AGENTS.md` "Local agent guardrails") | L2 / L2 | Edit code and run the checks (`make verify-module`) on a laptop. | `.claude/settings.json` + `.agents/hooks/guard.py` (tested): blocks apply, destroy, state edits and `run --all` without a read-only command; blocks edits to `.checkov.yaml`, `policy-library-repo/` and the hooks themselves; stops after 3 failed checks on a module. **Advisory: they run on a laptop and can be switched off.** The real control is that the laptop agent holds no apply credentials. |

Nothing above may assume `github-actions-apply`. Only the `apply` job in `terragrunt.yml` and `destroy.yml` uses it, and only from the
account's GitHub Environment (manual approval on prod).

## Known gaps

Written honestly, because an autonomy table that hides them is worse than none. Each gap links to what closes it.

1. **`main` is not protected.** `gh api repos/<owner>/<repo>/branches/main/protection` returns 404 and there are no rulesets (checked
   2026-09-29). So "a PR is required", the per-account required checks and CODEOWNERS review are **described in `docs/CICD.md`
   and `docs/GOVERNANCE.md` but not enforced by GitHub**. *Owner:* protect `main` (PR required, required checks, code-owner review, no bypass).
   Until then, every "a human merges" in this table depends on the human, not on the platform.
2. **CODEOWNERS does not protect the checks.** `.github/CODEOWNERS` has one global owner (`*`) and no separate entry for
   `.checkov.yaml`, `policy-library-repo/` or the workflows, and code-owner review is not required (gap 1). *Owner:* add those paths and require review.
3. **The healer pushes commits to someone else's PR branch.** It now stops at `main`, at a branch with no open PR, and after
   3 commits, and cannot edit protected paths (fixed in this change). It can still push a bad fix to a PR branch; the PR's own checks and
   review are what catch it. It labels the PR `ai-generated`.
4. **ChatOps could be triggered by anyone on this public repo** before this change (no author check, with LLM API secrets and a write token in the job).
   Fixed: only `OWNER`, `MEMBER` and `COLLABORATOR` comments run it. *Not fixed:* the comment text is a prompt to an LLM, so a collaborator's
   comment is trusted input.
5. **The hooks are advisory.** They can be disabled in a user's own settings. They are also **naive about quotes**: a command that only *mentions*
   a blocked command inside quotes is refused. A fix is proposed (quote-aware splitting) but the hook files are protected, so a human applies it.
6. **The IaC Generation Agent has a prod level of L1 by convention, not by a technical block**: `--env prod` is accepted from a comment. What stops
   it becoming more than a proposal is that no path applies and that a human merges (gap 1).
7. **Agent output is not scanned for secrets** before it is pushed. Checkov's secrets scan runs in CI on the PR, after the push.

## What would have to be true before L3

- `main` protected and every gap above closed or accepted in writing.
- 8 weeks of the weekly summary showing agent PRs with a change failure rate no worse than human PRs, with sample sizes large enough to mean something.
- A separate, narrower apply role for agents (not `github-actions-apply`), for non-prod accounts only, with its own permissions boundary.
- An ADR and the owner's sign-off.
