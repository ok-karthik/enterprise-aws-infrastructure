#!/usr/bin/env python3
"""Delivery metrics and platform SLOs for infrastructure changes (PLAN 9.3, 9.4, 11.5).

Reads GitHub history (PRs, workflow runs, drift issues) through the `gh` CLI and computes:

  DORA-style numbers   lead time, deployment frequency, change failure rate, drift MTTR
  Platform SLIs        the good/total counts behind the SLOs in docs/SLO.md
  Human vs agent       every number above split by the `ai-generated` PR label, with sample sizes (11.5)

Outputs a Markdown summary (for the drift issue or a step summary) and, with --write-json, a small status file that
.agents/scripts/iac_agent.py reads instead of the static budget in .agents/sre/error_budgets.yaml.

Numbers are for a team, never for a person: no author or reviewer name is read or printed.
The maths is pure functions over plain dicts, so it is tested offline (.agents/tests/test_delivery_metrics.py).
Only fetch() needs `gh` and a token.
"""
from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

BASE_DIR = Path(__file__).resolve().parent.parent
SLO_STATUS_PATH = BASE_DIR / "metrics" / "platform_slo.json"
AI_LABEL = "ai-generated"

# The SLOs (docs/SLO.md). `target` is the share of good events.
SLOS = {
    "pr_plan_speed": {"target": 0.99, "description": "PR plan runs finish in under 10 minutes"},
    "apply_success": {"target": 0.95, "description": "Applies on main succeed"},
    "drift_fixed": {"target": 0.90, "description": "Drift issues are closed within 5 working days"},
}
PLAN_LIMIT_SECONDS = 600
DRIFT_WORKING_DAYS = 5
REWORK_DAYS = 7


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def ts(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def hours(a: Optional[datetime], b: Optional[datetime]) -> Optional[float]:
    if a is None or b is None:
        return None
    return (b - a).total_seconds() / 3600


def median(values: list[float]) -> Optional[float]:
    return round(statistics.median(values), 2) if values else None


def working_days_between(start: datetime, end: datetime) -> int:
    """Whole weekdays from start to end (Mon-Fri only; holidays are not modelled)."""
    days, cursor = 0, start
    while cursor.date() < end.date():
        cursor += timedelta(days=1)
        if cursor.weekday() < 5:
            days += 1
    return days


def labels(item: dict) -> set[str]:
    return {label["name"] if isinstance(label, dict) else label for label in item.get("labels", [])}


def in_window(when: Optional[datetime], now: datetime, window_days: int) -> bool:
    return when is not None and now - when <= timedelta(days=window_days)


def budget_remaining_pct(good: int, total: int, target: float) -> Optional[float]:
    """Share of the error budget left. None when there are no events (unknown, not 100)."""
    if total == 0:
        return None
    allowed_bad = total * (1 - target)
    bad = total - good
    if allowed_bad == 0:
        return 100.0 if bad == 0 else 0.0
    return round(max(0.0, 1 - bad / allowed_bad) * 100, 1)


# ---------------------------------------------------------------------------
# PRs: lead time, time to first review, rework (reverts), split by the ai-generated label
# ---------------------------------------------------------------------------
def summarize_prs(prs: list[dict], now: datetime, window_days: int) -> dict:
    merged = [p for p in prs if in_window(ts(p.get("mergedAt")), now, window_days)]
    groups = {"human": [], "ai": []}
    for pr in merged:
        groups["ai" if AI_LABEL in labels(pr) else "human"].append(pr)

    # A revert PR ("Revert "<title>"") merged within REWORK_DAYS of the PR it reverts counts as rework for that PR.
    by_title = {p["title"]: p for p in merged}
    reworked: set[int] = set()
    for pr in merged:
        title = pr.get("title", "")
        if title.startswith("Revert "):
            original = by_title.get(title[len("Revert "):].strip('"'))
            if original and (h := hours(ts(original["mergedAt"]), ts(pr["mergedAt"]))) is not None and 0 <= h <= REWORK_DAYS * 24:
                reworked.add(original["number"])

    out = {}
    for name, items in groups.items():
        lead = [h for p in items if (h := hours(ts(p.get("createdAt")), ts(p.get("mergedAt")))) is not None]
        first_review = []
        for p in items:
            times = [ts(r.get("submittedAt")) for r in p.get("reviews", []) if r.get("submittedAt")]
            if times and (h := hours(ts(p.get("createdAt")), min(times))) is not None:
                first_review.append(h)
        out[name] = {
            "n": len(items),
            "lead_time_h_median": median(lead),
            "time_to_first_review_h_median": median(first_review),
            "reworked": sum(1 for p in items if p["number"] in reworked),
        }
    return out


# ---------------------------------------------------------------------------
# Workflow runs: deployment frequency, change failure rate, PR plan speed
# ---------------------------------------------------------------------------
def duration_seconds(run: dict) -> Optional[float]:
    start, end = ts(run.get("createdAt")), ts(run.get("updatedAt"))
    return (end - start).total_seconds() if start and end else None


def summarize_apply_runs(runs: list[dict], now: datetime, window_days: int) -> dict:
    """Runs of the main pipeline triggered by a push to main: each one is a deployment attempt."""
    recent = [r for r in runs if in_window(ts(r.get("createdAt")), now, window_days) and r.get("conclusion") in ("success", "failure")]
    ok = sum(1 for r in recent if r["conclusion"] == "success")
    failed = len(recent) - ok
    return {
        "n": len(recent),
        "successful": ok,
        "failed": failed,
        "deployments_per_week": round(ok / (window_days / 7), 2) if recent else None,
        "change_failure_rate": round(failed / len(recent), 3) if recent else None,
    }


def summarize_plan_runs(runs: list[dict], now: datetime, window_days: int) -> dict:
    recent = [r for r in runs if in_window(ts(r.get("createdAt")), now, window_days) and r.get("conclusion") in ("success", "failure")]
    durations = [d for r in recent if (d := duration_seconds(r)) is not None]
    fast = sum(1 for d in durations if d <= PLAN_LIMIT_SECONDS)
    return {"n": len(durations), "within_limit": fast, "duration_s_median": round(statistics.median(durations)) if durations else None}


# ---------------------------------------------------------------------------
# Drift issues: MTTR and "closed within 5 working days"
# ---------------------------------------------------------------------------
def summarize_drift(issues: list[dict], now: datetime, window_days: int) -> dict:
    relevant = [i for i in issues if in_window(ts(i.get("createdAt")), now, window_days) or not i.get("closedAt")]
    mttr, good, bad, open_over_7d = [], 0, 0, 0
    for issue in relevant:
        created, closed = ts(issue.get("createdAt")), ts(issue.get("closedAt"))
        if created is None:
            continue
        if closed:
            mttr.append(hours(created, closed))
            if working_days_between(created, closed) <= DRIFT_WORKING_DAYS:
                good += 1
            else:
                bad += 1
        else:
            if working_days_between(created, now) > DRIFT_WORKING_DAYS:
                bad += 1  # still open and already past the objective
            if (now - created).days > 7:
                open_over_7d += 1
    return {
        "n": good + bad,
        "closed_in_time": good,
        "mttr_h_median": median(mttr),
        "open_over_7_days": open_over_7d,
    }


# ---------------------------------------------------------------------------
# Cost per verified agent change (11.5)
# ---------------------------------------------------------------------------
def cost_per_verified_change(prs: list[dict], runs: list[dict], now: datetime, window_days: int, minute_cost_usd: float, llm_cost_usd: Optional[float]) -> dict:
    """(CI minutes + LLM cost) / agent PRs that passed CI and were merged. Review time is reported as time to first
    review elsewhere, not priced. LLM cost is None (not recorded) until the agent logs tokens."""
    agent_prs = [p for p in prs if AI_LABEL in labels(p) and in_window(ts(p.get("mergedAt")), now, window_days)]
    branches = {p.get("headRefName") for p in agent_prs}
    seconds = sum(d for r in runs if r.get("headBranch") in branches and (d := duration_seconds(r)) is not None)
    verified = len(agent_prs)
    if verified == 0:
        return {"verified_changes": 0, "ci_minutes": 0, "cost_per_change_usd": None, "llm_cost_recorded": llm_cost_usd is not None}
    ci_minutes = round(seconds / 60, 1)
    total = ci_minutes * minute_cost_usd + (llm_cost_usd or 0.0)
    return {
        "verified_changes": verified,
        "ci_minutes": ci_minutes,
        "cost_per_change_usd": round(total / verified, 2),
        "llm_cost_recorded": llm_cost_usd is not None,
    }


# ---------------------------------------------------------------------------
# SLO status
# ---------------------------------------------------------------------------
def slo_status(plan: dict, apply: dict, drift: dict, now: datetime) -> dict:
    counts = {
        "pr_plan_speed": (plan["within_limit"], plan["n"]),
        "apply_success": (apply["successful"], apply["n"]),
        "drift_fixed": (drift["closed_in_time"], drift["n"]),
    }
    slos = {}
    for name, (good, total) in counts.items():
        target = SLOS[name]["target"]
        slos[name] = {
            "description": SLOS[name]["description"],
            "target": target,
            "good": good,
            "total": total,
            "error_budget_remaining_pct": budget_remaining_pct(good, total, target),
        }
    return {"generated_at": now.isoformat(), "slos": slos, "error_budget_remaining_pct": slos["apply_success"]["error_budget_remaining_pct"]}


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def fmt(value, unit="") -> str:
    return "n/a" if value is None else f"{value}{unit}"


def render_markdown(report: dict) -> str:
    prs, apply, plan, drift, cost, slo = (report[k] for k in ("prs", "apply", "plan", "drift", "cost", "slo"))
    lines = [
        f"## Delivery metrics, last {report['window_days']} days",
        "",
        "Per team, never per person. Small samples are shown, not hidden: read a number with `n` under about 10 as a hint, not a result.",
        "",
        "### Pull requests: human vs agent (`ai-generated` label)",
        "",
        "| | n | median lead time (h) | median time to first review (h) | reverted within 7 days |",
        "|---|---|---|---|---|",
    ]
    for name, label in (("human", "Human"), ("ai", "Agent")):
        g = prs[name]
        lines.append(f"| {label} | {g['n']} | {fmt(g['lead_time_h_median'])} | {fmt(g['time_to_first_review_h_median'])} | {g['reworked']} |")
    lines += [
        "",
        "### Deployments and platform health",
        "",
        f"- Deployments per week: **{fmt(apply['deployments_per_week'])}** (n={apply['n']} runs on main)",
        f"- Change failure rate: **{fmt(apply['change_failure_rate'])}** ({apply['failed']} failed of {apply['n']})",
        f"- PR plan runs within 10 minutes: **{plan['within_limit']} of {plan['n']}** (median {fmt(plan['duration_s_median'], ' s')})",
        f"- Drift: median time to fix {fmt(drift['mttr_h_median'], ' h')}, {drift['closed_in_time']} of {drift['n']} fixed in {DRIFT_WORKING_DAYS} working days, {drift['open_over_7_days']} open over 7 days",
        "",
        "### Cost per verified agent change",
        "",
        f"- Agent PRs merged: {cost['verified_changes']}, CI minutes {cost['ci_minutes']}, cost per change: **{fmt(cost['cost_per_change_usd'], ' USD')}**"
        + ("" if cost["llm_cost_recorded"] else " (CI only: LLM tokens are not recorded yet)"),
        "",
        "### SLOs",
        "",
        "| SLO | target | good / total | error budget left |",
        "|---|---|---|---|",
    ]
    for name, s in slo["slos"].items():
        lines.append(f"| {s['description']} | {s['target']:.0%} | {s['good']} / {s['total']} | {fmt(s['error_budget_remaining_pct'], ' %')} |")
    lines.append("")
    return "\n".join(lines)


def build_report(prs: list[dict], plan_runs: list[dict], apply_runs: list[dict], issues: list[dict], now: datetime, window_days: int, minute_cost_usd: float = 0.008, llm_cost_usd: Optional[float] = None) -> dict:
    plan = summarize_plan_runs(plan_runs, now, window_days)
    apply = summarize_apply_runs(apply_runs, now, window_days)
    drift = summarize_drift(issues, now, window_days)
    return {
        "window_days": window_days,
        "prs": summarize_prs(prs, now, window_days),
        "apply": apply,
        "plan": plan,
        "drift": drift,
        "cost": cost_per_verified_change(prs, plan_runs + apply_runs, now, window_days, minute_cost_usd, llm_cost_usd),
        "slo": slo_status(plan, apply, drift, now),
    }


# ---------------------------------------------------------------------------
# GitHub access (the only part that needs `gh`)
# ---------------------------------------------------------------------------
def gh_json(args: list[str]):
    result = subprocess.run(["gh", *args], check=True, capture_output=True, text=True)
    return json.loads(result.stdout or "[]")


def fetch(repo: Optional[str], workflow: str) -> dict:
    repo_args = ["--repo", repo] if repo else []
    run_fields = "databaseId,conclusion,createdAt,updatedAt,headBranch,event"
    return {
        "prs": gh_json(["pr", "list", "--state", "merged", "--limit", "300", "--json", "number,title,createdAt,mergedAt,labels,reviews,headRefName", *repo_args]),
        "plan_runs": gh_json(["run", "list", "--workflow", workflow, "--event", "pull_request", "--limit", "300", "--json", run_fields, *repo_args]),
        "apply_runs": gh_json(["run", "list", "--workflow", workflow, "--event", "push", "--branch", "main", "--limit", "300", "--json", run_fields, *repo_args]),
        "issues": gh_json(["issue", "list", "--label", "drift", "--state", "all", "--limit", "300", "--json", "number,createdAt,closedAt", *repo_args]),
    }


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", help="owner/name (default: the current repository)")
    parser.add_argument("--workflow", default="terragrunt.yml")
    parser.add_argument("--window-days", type=int, default=28)
    parser.add_argument("--input", help="read a saved JSON file (keys prs, plan_runs, apply_runs, issues) instead of calling gh")
    parser.add_argument("--markdown", help="write the Markdown summary to this file (default: print it)")
    parser.add_argument("--write-json", nargs="?", const=str(SLO_STATUS_PATH), help="write the SLO status file the agent reads (default path .agents/metrics/platform_slo.json)")
    parser.add_argument("--minute-cost-usd", type=float, default=0.008, help="price of one CI minute (GitHub-hosted Linux runner list price; check yours)")
    args = parser.parse_args(argv)

    data = json.loads(Path(args.input).read_text()) if args.input else fetch(args.repo, args.workflow)
    now = datetime.now(timezone.utc)
    report = build_report(data["prs"], data["plan_runs"], data["apply_runs"], data["issues"], now, args.window_days, args.minute_cost_usd)
    text = render_markdown(report)
    if args.markdown:
        Path(args.markdown).write_text(text)
    else:
        print(text)
    if args.write_json:
        Path(args.write_json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.write_json).write_text(json.dumps(report["slo"], indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
