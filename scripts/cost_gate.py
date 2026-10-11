#!/usr/bin/env python3
"""Fail a pull request whose monthly cost rises too much, unless it carries an approval label (PLAN 9.5).

Reads the combined Infracost JSON (`infracost output --format json`) and compares the new monthly cost with the
past one. A rise breaches the gate when it is at least --max-usd, or at least --min-usd AND at least --max-pct
percent of the past cost. The floor (--min-usd) stops "+$1 on a $4 sandbox" from failing every PR. A cost
decrease never breaches. A label named --approve-label turns a breach into a pass (the label is read live in CI).

Infracost writes money as strings ("123.45"), or null when nothing is priced, so numbers, strings and null are
all accepted.

Exit codes: 0 pass or approved, 1 breached and not approved, 2 bad input.
"""
import argparse
import json
import sys
from dataclasses import dataclass


@dataclass
class Verdict:
    past: float
    total: float
    diff: float
    pct: float | None  # None when the past cost is 0 (a percentage means nothing then)
    breached: bool
    reason: str


def to_float(v) -> float:
    if v is None or v == "":
        return 0.0
    if isinstance(v, bool) or not isinstance(v, (str, int, float)):
        raise ValueError(f"not a number: {v!r}")
    return float(v)


def evaluate(data: dict, max_usd: float, min_usd: float, max_pct: float) -> Verdict:
    past = to_float(data.get("pastTotalMonthlyCost"))
    total = to_float(data.get("totalMonthlyCost"))
    if data.get("diffTotalMonthlyCost") is None:
        diff = total - past
    else:
        diff = to_float(data.get("diffTotalMonthlyCost"))
    pct = (diff / past * 100) if past > 0 else None

    if diff >= max_usd:
        return Verdict(past, total, diff, pct, True, f"rise of ${diff:.2f} is at least ${max_usd:.2f}")
    if diff >= min_usd and pct is not None and pct >= max_pct:
        return Verdict(past, total, diff, pct, True, f"rise of ${diff:.2f} is at least ${min_usd:.2f} and {pct:.1f}% is at least {max_pct:g}%")
    return Verdict(past, total, diff, pct, False, "under the threshold")


def top_projects(data: dict, n: int = 5) -> list[tuple[str, float]]:
    rows = []
    for p in data.get("projects") or []:
        diff = p.get("diff") or {}
        rows.append((p.get("name") or "(unnamed)", to_float(diff.get("totalMonthlyCost"))))
    rows.sort(key=lambda r: r[1], reverse=True)
    return rows[:n]


def render(v: Verdict, status: str, rule: str, projects: list[tuple[str, float]]) -> str:
    icon = {"pass": "✅ pass", "approved": "⚠️ over threshold, approved by label", "fail": "❌ over threshold"}[status]
    pct = f"{v.pct:+.1f}%" if v.pct is not None else "n/a"
    lines = [
        "",
        f"### 💸 Cost gate: {icon}",
        "",
        f"Monthly: ${v.past:.2f} → ${v.total:.2f} ({v.diff:+.2f} USD, {pct})",
        "",
        f"Rule: {rule}",
    ]
    if projects:
        lines += ["", "Top projects by monthly change:"]
        lines += [f"- {name}: {diff:+.2f} USD" for name, diff in projects]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("infracost_json")
    ap.add_argument("--labels", default="", help="comma-separated PR label names")
    ap.add_argument("--max-usd", type=float, default=100.0)
    ap.add_argument("--min-usd", type=float, default=10.0)
    ap.add_argument("--max-pct", type=float, default=20.0)
    ap.add_argument("--approve-label", default="cost-approved")
    ap.add_argument("--markdown-out")
    args = ap.parse_args(argv)

    try:
        with open(args.infracost_json) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
        verdict = evaluate(data, args.max_usd, args.min_usd, args.max_pct)
        projects = top_projects(data)
    except (OSError, ValueError, AttributeError, TypeError, KeyError) as e:  # json.JSONDecodeError is a ValueError; the rest are odd shapes
        print(f"cost gate: bad input: {e}", file=sys.stderr)
        return 2

    labels = {x.strip() for x in args.labels.split(",") if x.strip()}
    if not verdict.breached:
        status = "pass"
    elif args.approve_label in labels:
        status = "approved"
    else:
        status = "fail"

    rule = (
        f"fail when the monthly rise is at least ${args.max_usd:g}, or at least ${args.min_usd:g} and at least "
        f"{args.max_pct:g}% of the past cost; the `{args.approve_label}` label approves."
    )
    pct = f"{verdict.pct:+.1f}%" if verdict.pct is not None else "n/a"
    label_text = {"pass": "pass", "approved": "over threshold, approved by label", "fail": "over threshold, NOT approved"}[status]
    print(f"cost gate: {label_text}: ${verdict.past:.2f} -> ${verdict.total:.2f} ({verdict.diff:+.2f} USD, {pct}); {verdict.reason}")

    if args.markdown_out:
        with open(args.markdown_out, "a") as f:
            f.write(render(verdict, status, rule, projects))
    return 1 if status == "fail" else 0


if __name__ == "__main__":
    sys.exit(main())
