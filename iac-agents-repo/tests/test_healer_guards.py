#!/usr/bin/env python3
"""Tests for the healer's hard limits (PLAN 11.2 / 11.4): never main, only with an open PR, at most N commits, no
protected paths. Pure functions, offline."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ci_healer"))
import healer_guards as g  # noqa: E402

OK_PATHS = ["iac-modules-repo/network/vpc/.terraform.lock.hcl", "workloads-live-repo/workloads/nonprod/workloads-dev/eu-central-1/network/vpc/terragrunt.hcl"]


class PushDecision(unittest.TestCase):
    def test_a_normal_fix_on_a_pr_branch_is_allowed(self):
        self.assertEqual(g.push_decision("feat/p7-thing", 42, 0, OK_PATHS), (True, "ok"))

    def test_main_is_refused_even_with_a_pr_number(self):
        for branch in ["main", "master"]:
            allowed, reason = g.push_decision(branch, 42, 0, OK_PATHS)
            self.assertFalse(allowed)
            self.assertIn("never commits to the main branch", reason)

    def test_a_branch_without_an_open_pr_is_refused(self):
        allowed, reason = g.push_decision("feat/orphan", None, 0, OK_PATHS)
        self.assertFalse(allowed)
        self.assertIn("no open pull request", reason)

    def test_the_commit_cap_is_three(self):
        self.assertEqual(g.MAX_HEALER_COMMITS, 3)
        self.assertTrue(g.push_decision("b", 1, 2, OK_PATHS)[0])
        allowed, reason = g.push_decision("b", 1, 3, OK_PATHS)
        self.assertFalse(allowed)
        self.assertIn("limit 3", reason)

    def test_a_missing_branch_name_is_refused(self):
        self.assertFalse(g.push_decision("", 1, 0, OK_PATHS)[0])
        self.assertFalse(g.push_decision(None, 1, 0, OK_PATHS)[0])

    def test_protected_paths_stop_the_push(self):
        for path in [".checkov.yaml", "policy-library-repo/terraform/require_tags.rego", ".github/workflows/terragrunt.yml", ".trivyignore", ".tflint.hcl", "sub/.trivyignore", ".claude/settings.json", ".claude/hooks/guard.py", "./.checkov.yaml"]:
            allowed, reason = g.push_decision("b", 1, 0, OK_PATHS + [path])
            self.assertFalse(allowed, path)
            self.assertIn("protected paths", reason)


class Helpers(unittest.TestCase):
    def test_only_healer_commits_are_counted(self):
        subjects = ["feat(vpc): x", "chore(ci): auto-remediate pipeline failure", "chore(ci): auto-upgrade terraform provider lock files", "fix: y", "chore(ci): pin action"]
        self.assertEqual(g.count_healer_commits(subjects), 2)

    def test_the_commit_messages_the_runner_uses_match_the_counter(self):
        text = (Path(__file__).resolve().parent.parent / "ci_healer" / "healer_runner.py").read_text()
        for message in ("chore(ci): auto-upgrade terraform provider lock files", "chore(ci): auto-remediate pipeline failure"):
            self.assertIn(message, text)
            self.assertTrue(message.startswith(g.HEALER_COMMIT_PREFIX), message)

    def test_the_ai_label_is_the_one_the_metrics_use(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / ".github" / "scripts"))
        import delivery_metrics
        self.assertEqual(g.AI_LABEL, delivery_metrics.AI_LABEL)


if __name__ == "__main__":
    unittest.main()
