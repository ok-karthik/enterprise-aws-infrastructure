#!/usr/bin/env python3
"""Offline tests for delivery_metrics.py and the measured error budget (PLAN 9.3, 9.4, 11.5). No gh, no network."""

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR / "scripts"))

import delivery_metrics as dm  # noqa: E402
import iac_agent  # noqa: E402

NOW = datetime(2026, 10, 14, 12, 0, tzinfo=timezone.utc)  # a Wednesday


def iso(days_ago=0.0, hours_ago=0.0):
    return (NOW - timedelta(days=days_ago, hours=hours_ago)).isoformat()


def pr(number, title, created_h_before_merge, merged_days_ago, labels_=(), first_review_h=None, branch=None):
    merged = NOW - timedelta(days=merged_days_ago)
    created = merged - timedelta(hours=created_h_before_merge)
    reviews = [] if first_review_h is None else [{"submittedAt": (created + timedelta(hours=first_review_h)).isoformat()}]
    return {"number": number, "title": title, "createdAt": created.isoformat(), "mergedAt": merged.isoformat(), "labels": [{"name": n} for n in labels_], "reviews": reviews, "headRefName": branch or f"b{number}"}


def run(conclusion, days_ago, seconds=300, branch="main"):
    created = NOW - timedelta(days=days_ago)
    return {"conclusion": conclusion, "createdAt": created.isoformat(), "updatedAt": (created + timedelta(seconds=seconds)).isoformat(), "headBranch": branch}


class Helpers(unittest.TestCase):
    def test_working_days_skip_weekends(self):
        friday = datetime(2026, 10, 9, 9, 0, tzinfo=timezone.utc)
        monday = datetime(2026, 10, 12, 9, 0, tzinfo=timezone.utc)
        self.assertEqual(dm.working_days_between(friday, monday), 1)
        self.assertEqual(dm.working_days_between(friday, friday + timedelta(days=7)), 5)

    def test_budget_maths(self):
        self.assertEqual(dm.budget_remaining_pct(100, 100, 0.99), 100.0)
        self.assertEqual(dm.budget_remaining_pct(99, 100, 0.99), 0.0)  # exactly the whole budget used
        self.assertEqual(dm.budget_remaining_pct(198, 200, 0.99), 0.0)
        self.assertEqual(dm.budget_remaining_pct(196, 200, 0.98), 0.0)
        self.assertEqual(dm.budget_remaining_pct(99, 100, 0.95), 80.0)
        self.assertIsNone(dm.budget_remaining_pct(0, 0, 0.99), "no events means unknown, never 100")


class PullRequests(unittest.TestCase):
    def test_human_and_agent_are_split_with_sample_sizes(self):
        prs = [
            pr(1, "feat: a", 10, 3, first_review_h=2),
            pr(2, "feat: b", 20, 2, first_review_h=4),
            pr(3, "feat: c", 5, 1, labels_=["ai-generated"], first_review_h=1),
            pr(4, "old", 5, 60),  # outside the window
        ]
        out = dm.summarize_prs(prs, NOW, 28)
        self.assertEqual(out["human"]["n"], 2)
        self.assertEqual(out["ai"]["n"], 1)
        self.assertEqual(out["human"]["lead_time_h_median"], 15.0)
        self.assertEqual(out["human"]["time_to_first_review_h_median"], 3.0)

    def test_a_revert_within_seven_days_counts_as_rework_for_the_original(self):
        prs = [
            pr(10, "feat: risky", 4, 3, labels_=["ai-generated"]),
            pr(11, 'Revert "feat: risky"', 1, 2),
            pr(12, "feat: fine", 4, 3),
        ]
        out = dm.summarize_prs(prs, NOW, 28)
        self.assertEqual(out["ai"]["reworked"], 1)
        self.assertEqual(out["human"]["reworked"], 0)

    def test_no_names_are_read(self):
        text = json.dumps(dm.summarize_prs([pr(1, "x", 1, 1)], NOW, 28))
        self.assertNotIn("author", text)


class Runs(unittest.TestCase):
    def test_apply_runs_give_frequency_and_failure_rate(self):
        runs = [run("success", 1), run("success", 3), run("failure", 5), run("cancelled", 6), run("success", 40)]
        out = dm.summarize_apply_runs(runs, NOW, 28)
        self.assertEqual((out["n"], out["successful"], out["failed"]), (3, 2, 1))
        self.assertEqual(out["change_failure_rate"], 0.333)
        self.assertEqual(out["deployments_per_week"], 0.5)

    def test_plan_speed_counts_runs_over_ten_minutes(self):
        runs = [run("success", 1, 300), run("success", 2, 601), run("failure", 3, 900)]
        out = dm.summarize_plan_runs(runs, NOW, 28)
        self.assertEqual((out["n"], out["within_limit"]), (3, 1))


class Drift(unittest.TestCase):
    def test_closed_in_time_late_and_still_open(self):
        issues = [
            {"createdAt": iso(days_ago=10), "closedAt": iso(days_ago=9)},  # fixed in 1 day
            {"createdAt": iso(days_ago=20), "closedAt": iso(days_ago=5)},  # 15 days: late
            {"createdAt": iso(days_ago=12), "closedAt": None},  # open and long past the objective
            {"createdAt": iso(days_ago=1), "closedAt": None},  # open, still inside it
        ]
        out = dm.summarize_drift(issues, NOW, 28)
        self.assertEqual((out["n"], out["closed_in_time"]), (3, 1))
        self.assertEqual(out["open_over_7_days"], 1)


class Cost(unittest.TestCase):
    def test_cost_per_verified_agent_change(self):
        prs = [pr(1, "a", 1, 1, labels_=["ai-generated"], branch="agent/iac-x"), pr(2, "b", 1, 1)]
        runs = [run("success", 1, 600, branch="agent/iac-x"), run("success", 1, 600, branch="other")]
        out = dm.cost_per_verified_change(prs, runs, NOW, 28, minute_cost_usd=0.01, llm_cost_usd=None)
        self.assertEqual((out["verified_changes"], out["ci_minutes"]), (1, 10.0))
        self.assertEqual(out["cost_per_change_usd"], 0.1)
        self.assertFalse(out["llm_cost_recorded"])

    def test_no_agent_changes_means_no_number(self):
        out = dm.cost_per_verified_change([pr(2, "b", 1, 1)], [], NOW, 28, 0.01, None)
        self.assertIsNone(out["cost_per_change_usd"])


class ReportAndGate(unittest.TestCase):
    def setUp(self):
        self.report = dm.build_report([pr(1, "a", 2, 1)], [run("success", 1)], [run("success", 1)] * 19 + [run("failure", 2)], [], NOW, 28)

    def test_markdown_shows_both_groups_and_sample_sizes(self):
        text = dm.render_markdown(self.report)
        self.assertIn("| Human | 1 |", text)
        self.assertIn("| Agent | 0 |", text)
        self.assertIn("Per team, never per person", text)

    def test_status_file_feeds_the_agent_gate(self):
        status = self.report["slo"]
        self.assertEqual(status["error_budget_remaining_pct"], status["slos"]["apply_success"]["error_budget_remaining_pct"], "the gate uses the apply-success SLO")
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "platform_slo.json"
            path.write_text(json.dumps({"generated_at": NOW.isoformat(), "error_budget_remaining_pct": 42.5}))
            os.environ.pop("SLO_ERROR_BUDGET_REMAINING", None)
            self.assertEqual(iac_agent.measured_error_budget({"error_budget_remaining_pct": 92.5}, NOW, path), 42.5)

    def test_gate_ignores_a_stale_or_missing_status_file_and_honours_the_override(self):
        cfg = {"error_budget_remaining_pct": 92.5}
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "platform_slo.json"
            os.environ.pop("SLO_ERROR_BUDGET_REMAINING", None)
            self.assertEqual(iac_agent.measured_error_budget(cfg, NOW, path), 92.5, "missing file falls back to the static number")
            path.write_text(json.dumps({"generated_at": (NOW - timedelta(days=30)).isoformat(), "error_budget_remaining_pct": 1.0}))
            self.assertEqual(iac_agent.measured_error_budget(cfg, NOW, path), 92.5, "a month-old measurement is not trusted")
            path.write_text(json.dumps({"generated_at": NOW.isoformat(), "error_budget_remaining_pct": None}))
            self.assertEqual(iac_agent.measured_error_budget(cfg, NOW, path), 92.5, "an unknown (no events) budget is not treated as measured")
            os.environ["SLO_ERROR_BUDGET_REMAINING"] = "5"
            try:
                self.assertEqual(iac_agent.measured_error_budget(cfg, NOW, path), 5.0)
            finally:
                os.environ.pop("SLO_ERROR_BUDGET_REMAINING", None)


if __name__ == "__main__":
    unittest.main()
