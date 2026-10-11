import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cost_report as r  # noqa: E402


def day(groups):
    return {"Groups": [{"Keys": [k], "Metrics": {"UnblendedCost": {"Amount": str(v)}}} for k, v in groups.items()]}


class FakeCE:
    def __init__(self, pages=None, active=True):
        self.pages = pages or [{"ResultsByTime": []}]
        self.calls = []
        self.tag_calls = []
        self.active = active

    def get_cost_and_usage(self, **kw):
        self.calls.append(kw)
        return self.pages[len(self.calls) - 1]

    def list_cost_allocation_tags(self, **kw):
        self.tag_calls.append(kw)
        status = "Active" if self.active else "Inactive"
        return {"CostAllocationTags": [{"TagKey": "CostCenter", "Status": status}]}


class ClientErrorLike(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeCOH:
    def __init__(self, items=None, error=None, pages=None):
        self.items, self.error, self.pages = items or [], error, pages
        self.calls = 0

    def list_recommendations(self, **kw):
        if self.error:
            raise ClientErrorLike(self.error)
        if self.pages:
            self.calls += 1
            return self.pages[self.calls - 1]
        return {"items": self.items}


def rec(rid, usd):
    return {"accountId": "111111111111", "currentResourceType": "Ec2Instance", "actionType": "Rightsize", "resourceId": rid, "estimatedMonthlySavings": usd}


class CostReport(unittest.TestCase):
    def test_windows_for_a_monday(self):
        self.assertEqual(r.week_windows(date(2026, 10, 12)), ("2026-10-05", "2026-10-12", "2026-09-28", "2026-10-05"))

    def test_pagination_is_followed_and_days_are_summed(self):
        ce = FakeCE(pages=[
            {"ResultsByTime": [day({"EC2": 1.5})], "NextPageToken": "t"},
            {"ResultsByTime": [day({"EC2": 2.0, "S3": 1})]},
        ])
        out = r.cost_by(ce, "2026-10-05", "2026-10-12", "SERVICE", "DIMENSION")
        self.assertEqual(out, {"EC2": 3.5, "S3": 1.0})
        self.assertEqual(len(ce.calls), 2)
        self.assertEqual(ce.calls[1]["NextPageToken"], "t")
        self.assertEqual(ce.calls[0]["GroupBy"], [{"Type": "DIMENSION", "Key": "SERVICE"}])

    def test_untagged_share(self):
        self.assertAlmostEqual(r.untagged_share({"CostCenter$": 25.0, "CostCenter$team-a": 75.0}), 25.0)
        self.assertEqual(r.untagged_share({}), 0.0)

    def test_not_activated_note_replaces_percentage(self):
        w = r.week_windows(date(2026, 10, 12))
        text = r.render(w, ({"A": 1.0}, {"A": 1.0}), ({}, {}), {"CostCenter$": 1.0}, False, [], None)
        self.assertIn("not activated", text)
        self.assertNotIn("100.0 %", text)

    def test_costcenter_active(self):
        self.assertTrue(r.costcenter_active(FakeCE(active=True)))
        self.assertFalse(r.costcenter_active(FakeCE(active=False)))

    def test_top_movers_order_new_key_and_decrease(self):
        rows = r.top_movers({"A": 10, "B": 50, "C": 5}, {"A": 12, "B": 20, "D": 40})
        self.assertEqual([x["key"] for x in rows], ["D", "B", "C", "A"])
        self.assertTrue([x for x in rows if x["key"] == "C"][0]["new"])
        self.assertLess([x for x in rows if x["key"] == "D"][0]["change"], 0)

    def test_savings_sorted_capped_and_paginated(self):
        items1 = [rec(f"i-{i}", i) for i in range(4)]
        items2 = [rec(f"i-{i}", i) for i in range(4, 9)]
        coh = FakeCOH(pages=[{"items": items1, "nextToken": "n"}, {"items": items2}])
        rows, err = r.savings(coh)
        self.assertIsNone(err)
        self.assertEqual(len(rows), 5)
        self.assertEqual([x["estimatedMonthlySavings"] for x in rows], [8, 7, 6, 5, 4])

    def test_coh_error_gives_not_available_line(self):
        rows, err = r.savings(FakeCOH(error="AccessDeniedException"))
        self.assertEqual((rows, err), ([], "AccessDeniedException"))
        w = r.week_windows(date(2026, 10, 12))
        text = r.render(w, ({}, {}), ({}, {}), {}, True, rows, err)
        self.assertIn("Cost Optimization Hub: not available (`AccessDeniedException`)", text)

    def test_non_client_errors_are_not_swallowed(self):
        class Boom:
            def list_recommendations(self, **kw):
                raise RuntimeError("x")

        with self.assertRaises(RuntimeError):
            r.savings(Boom())

    def test_render_has_every_section(self):
        w = r.week_windows(date(2026, 10, 12))
        recs = [{"accountId": "1", "resourceType": "Ec2Instance", "actionType": "Rightsize", "resourceId": "i-1", "estimatedMonthlySavings": 12.0}]
        text = r.render(w, ({"EC2": 5.0}, {"EC2": 4.0}), ({"1": 5.0}, {"1": 4.0}), {"CostCenter$": 1.0}, True, recs, None)
        for h in ["# Weekly cost report", "## Top services by change", "## Top accounts by change", "## Untagged spend", "## Savings recommendations", "finops-weekly.yml"]:
            self.assertIn(h, text)

    def test_build_makes_five_usage_calls_and_one_tag_call(self):
        ce = FakeCE(pages=[{"ResultsByTime": [day({"X": 1})]}] * 5)
        text = r.build(ce, FakeCOH(error="AccessDeniedException"), date(2026, 10, 12))
        self.assertEqual(len(ce.calls), 5)
        self.assertEqual(len(ce.tag_calls), 1)
        self.assertIn("not available", text)


if __name__ == "__main__":
    unittest.main()
