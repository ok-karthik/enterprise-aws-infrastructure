#!/usr/bin/env python3
"""Weekly cost report as Markdown, from Cost Explorer and Cost Optimization Hub (PLAN 9.5).

Reads the last 7 full days against the 7 days before: top services, top accounts, the share of spend without a
CostCenter tag, and the biggest savings recommendations. It only writes Markdown; the workflow
(`.github/workflows/finops-weekly.yml`) turns that into a GitHub Issue. Read-only AWS calls, 6 Cost Explorer
requests per run (about $0.06).

boto3 is imported inside main() only, so the tests run without it. Every AWS-facing function takes a client.

Usage: cost_report.py --out FILE [--today YYYY-MM-DD]
"""
import argparse
import sys
from datetime import date, timedelta

COST_CENTER_TAG = "CostCenter"


def week_windows(today: date) -> tuple[str, str, str, str]:
    """Current window = the 7 full days ending yesterday. End is exclusive in Cost Explorer, so cur_end = today."""
    cur_end = today
    cur_start = today - timedelta(days=7)
    prev_end = cur_start
    prev_start = prev_end - timedelta(days=7)
    return tuple(d.isoformat() for d in (cur_start, cur_end, prev_start, prev_end))  # type: ignore[return-value]


def cost_by(ce, start: str, end: str, group_key: str, group_type: str) -> dict[str, float]:
    totals: dict[str, float] = {}
    token = None
    while True:
        kwargs = {
            "TimePeriod": {"Start": start, "End": end},
            "Granularity": "DAILY",
            "Metrics": ["UnblendedCost"],
            "GroupBy": [{"Type": group_type, "Key": group_key}],
        }
        if token:
            kwargs["NextPageToken"] = token
        resp = ce.get_cost_and_usage(**kwargs)
        for day in resp.get("ResultsByTime", []):
            for group in day.get("Groups", []):
                key = group["Keys"][0]
                totals[key] = totals.get(key, 0.0) + float(group["Metrics"]["UnblendedCost"]["Amount"])
        token = resp.get("NextPageToken")
        if not token:
            return totals


def untagged_share(tag_costs: dict[str, float]) -> float:
    """Cost Explorer returns tag keys as 'CostCenter$<value>'; untagged is 'CostCenter$'."""
    total = sum(tag_costs.values())
    if total <= 0:
        return 0.0
    return tag_costs.get(f"{COST_CENTER_TAG}$", 0.0) / total * 100


def costcenter_active(ce) -> bool:
    resp = ce.list_cost_allocation_tags(TagKeys=[COST_CENTER_TAG])
    return any(t.get("Status") == "Active" for t in resp.get("CostAllocationTags", []))


def top_movers(cur: dict[str, float], prev: dict[str, float], n: int = 5) -> list[dict]:
    rows = []
    for key in set(cur) | set(prev):
        c, p = cur.get(key, 0.0), prev.get(key, 0.0)
        rows.append({"key": key, "cur": c, "prev": p, "change": c - p, "new": key not in prev})
    rows.sort(key=lambda r: abs(r["change"]), reverse=True)
    return rows[:n]


def savings(coh, n: int = 5):
    """Returns (rows, error_code). Any boto ClientError gives ([], code); detected by .response, so botocore is not imported."""
    rows = []
    token = None
    try:
        while True:
            kwargs = {"nextToken": token} if token else {}
            resp = coh.list_recommendations(**kwargs)
            for r in resp.get("items", []):
                rows.append({
                    "accountId": r.get("accountId"),
                    "resourceType": r.get("currentResourceType") or r.get("resourceType"),
                    "actionType": r.get("actionType"),
                    "resourceId": r.get("resourceId"),
                    "estimatedMonthlySavings": float(r.get("estimatedMonthlySavings") or 0),
                })
            token = resp.get("nextToken")
            if not token:
                break
    except Exception as e:  # noqa: BLE001
        if hasattr(e, "response"):
            return [], e.response.get("Error", {}).get("Code", "Unknown")
        raise
    rows.sort(key=lambda r: r["estimatedMonthlySavings"], reverse=True)
    return rows[:n], None


def _fmt_change(r: dict) -> str:
    if r["new"]:
        return f"${r['cur']:.2f} (new)"
    pct = f" ({r['change'] / r['prev'] * 100:+.0f} %)" if r["prev"] > 0 else ""
    return f"${r['cur']:.2f} ({r['change']:+.2f} USD{pct})"


def _movers_table(rows: list[dict]) -> list[str]:
    if not rows:
        return ["No cost data."]
    return [f"- {r['key']}: {_fmt_change(r)}" for r in rows]


def render(windows, services, accounts, tag_costs, tag_active, recs, recs_error) -> str:
    cur_start, cur_end, prev_start, prev_end = windows
    cur_total = sum(v for v in (services[0] or {}).values())
    prev_total = sum(v for v in (services[1] or {}).values())
    lines = [
        "# Weekly cost report",
        "",
        f"Window: {cur_start} to {cur_end} (end excluded), compared with {prev_start} to {prev_end}.",
        "",
        f"Total this week: ${cur_total:.2f}. Last week: ${prev_total:.2f}.",
        "",
        "## Top services by change",
        "",
        *_movers_table(top_movers(services[0], services[1])),
        "",
        "## Top accounts by change",
        "",
        *_movers_table(top_movers(accounts[0], accounts[1])),
        "",
        "## Untagged spend",
        "",
    ]
    if tag_active:
        lines.append(f"{untagged_share(tag_costs):.1f} % of this week's spend has no `{COST_CENTER_TAG}` tag.")
    else:
        lines.append(
            f"{COST_CENTER_TAG} is not activated as a cost allocation tag yet, so all spend shows as untagged "
            "(see the billing leaf's step 2)."
        )
    lines += ["", "## Savings recommendations", ""]
    if recs_error:
        lines.append(
            f"Cost Optimization Hub: not available (`{recs_error}`). It is enabled by `governance/billing` "
            "(PLAN 9.5 Part 3) once that is applied."
        )
    elif not recs:
        lines.append("No recommendations.")
    else:
        top = recs[:5]
        for r in top:
            lines.append(
                f"- ${r['estimatedMonthlySavings']:.2f}/month: {r['actionType']} on {r['resourceType']} "
                f"`{r['resourceId']}` (account {r['accountId']})"
            )
        lines += ["", f"Total of the top {len(top)}: ${sum(r['estimatedMonthlySavings'] for r in top):.2f}/month."]
    lines += [
        "",
        "---",
        "Generated by `.github/workflows/finops-weekly.yml` (PLAN 9.5). "
        "Cost Explorer API cost for this report: about $0.06.",
        "",
    ]
    return "\n".join(lines)


def build(ce, coh, today: date) -> str:
    w = week_windows(today)
    cur_s, cur_e, prev_s, prev_e = w
    services = (cost_by(ce, cur_s, cur_e, "SERVICE", "DIMENSION"), cost_by(ce, prev_s, prev_e, "SERVICE", "DIMENSION"))
    accounts = (
        cost_by(ce, cur_s, cur_e, "LINKED_ACCOUNT", "DIMENSION"),
        cost_by(ce, prev_s, prev_e, "LINKED_ACCOUNT", "DIMENSION"),
    )
    tag_costs = cost_by(ce, cur_s, cur_e, COST_CENTER_TAG, "TAG")
    active = costcenter_active(ce)
    recs, err = savings(coh)
    return render(w, services, accounts, tag_costs, active, recs, err)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--today", help="YYYY-MM-DD, for testing")
    args = ap.parse_args(argv)
    today = date.fromisoformat(args.today) if args.today else date.today()

    import boto3  # noqa: PLC0415  (kept out of module scope so tests run without boto3)

    try:
        ce = boto3.client("ce", region_name="us-east-1")
        coh = boto3.client("cost-optimization-hub", region_name="us-east-1")
        text = build(ce, coh, today)
    except Exception as e:  # noqa: BLE001
        print(f"cost report failed: {e}", file=sys.stderr)
        return 1
    with open(args.out, "w") as f:
        f.write(text)
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
