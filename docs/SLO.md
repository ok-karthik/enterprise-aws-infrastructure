# Platform SLOs (PLAN 9.3)

Service level objectives for the *foundation itself*: the pipeline and the guardrails, not the applications on it.
Each SLO has a definition anyone can recompute, a target, and the data it comes from. The numbers are computed weekly by
`.github/scripts/delivery_metrics.py` (workflow `delivery-metrics.yml`).

**Status: the targets are proposals. Nothing has been measured yet.** The first weekly run fills in the real
numbers; adjust a target only after seeing them, and write down why.

| # | SLO | Target | Good event | Total events | Source |
|---|---|---|---|---|---|
| 1 | PR plans are fast | 99% | a PR run of `terragrunt.yml` that finishes in 10 minutes or less | PR runs that ended in success or failure | GitHub Actions run history |
| 2 | Applies on main succeed | 95% | a push-to-main run that succeeds | push-to-main runs that succeeded or failed (cancelled runs are ignored) | GitHub Actions run history |
| 3 | Drift is fixed | 90% | a drift issue closed within 5 working days | drift issues opened in the window, plus any still open past 5 working days | GitHub issues labelled `drift` |
| 4 | A new account is vended in under 1 hour | 95% | an account-factory apply that finishes in under 1 hour | account-factory applies | **not measured yet**: needs the account factory to be applied first |

Working days are Monday to Friday; holidays are not modelled.

## Error budget

For an SLO with target `T` and `N` events, the budget is `N x (1 - T)` bad events. Budget left = `1 - bad / budget`, as a
percentage, never below 0. With no events the budget is **unknown**, not 100%.

Example: 200 applies at 95% allow 10 failures. 4 failures leaves 60%.

## How it connects to the agent gate

`iac-agents-repo/iac_agent/iac_agent.py` freezes prod changes proposed by the agent when the prod error budget drops below the
`critical_threshold_pct` in `iac-agents-repo/sre/error_budgets.yaml`. Until now that number was typed into the YAML. Now it
is taken, in this order:

1. `SLO_ERROR_BUDGET_REMAINING` in the environment: an explicit human override.
2. `iac-agents-repo/metrics/platform_slo.json`, written by the weekly job from SLO 2 (applies on main succeed), **if it is at most
   8 days old and has a number**.
3. The static value in `error_budgets.yaml` (the old behaviour, and what is used until something is measured).

The status file is git-ignored: it is a measurement, not configuration. Run
`python3 .github/scripts/delivery_metrics.py --write-json` to refresh it locally (needs `gh`).

## Guardrail signals (alarms)

Separate from the four SLOs, `iac-modules-repo/observability/guardrail-signals` alarms when a control is weakened
(CloudTrail stopped, Config recorder stopped, GuardDuty or Security Hub disabled, root or BreakGlassAdmin used). Any
event is an incident, so these are alarms, not budgets. One dashboard ("are the guardrails on?") shows them in the
observability account.

Not covered, on purpose: CloudTrail *delivery* failures (CloudTrail publishes no metric for them; use the trail's
`sns_topic_arn` notifications) and "drift open for more than 7 days" (a GitHub signal: the weekly summary lists it, and
`delivery_metrics.py` already reports the count of open drift issues older than 7 days).

## What these numbers cannot tell you

- SLO 1 measures the whole workflow run (queueing included), which is what a developer waits for, but it is not the
  plan job alone.
- A "successful apply" only means the pipeline finished. It says nothing about whether the change was right.
- Small samples move the budget a lot: with 10 applies, a 95% target allows 0.5 failures, so a single failure uses the whole budget twice over.
