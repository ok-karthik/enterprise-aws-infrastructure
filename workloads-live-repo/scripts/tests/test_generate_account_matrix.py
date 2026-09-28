"""Unit tests for generate_account_matrix.py (no AWS access, no network)."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "generate_account_matrix.py"
spec = importlib.util.spec_from_file_location("generate_account_matrix", SCRIPT)
gam = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gam)

REGISTRY = """
locals {
  accounts = {
    management = {
      id     = "954171757349"
      ou     = "Root"
      env    = "global"
      create = false
      ci     = true # set once imported
    }
    log-archive = {
      id     = "111111111111"
      ou     = "Security"
      env    = "global"
      create = true
      ci     = true
    }
    workloads-prod = {
      id     = "333333333333"
      ou     = "Prod"
      env    = "prod"
      create = true
      ci     = true
    }
    workloads-dev = {
      id     = "222222222222"
      ou     = "NonProd"
      env    = "dev"
      create = true
      ci     = true
    }
    workloads-staging = {
      id     = "444444444444"
      ou     = "NonProd"
      env    = "staging"
      create = true
      ci     = false
    }
    network-hub = {
      id     = "000000000003"
      ou     = "Infrastructure"
      env    = "global"
      create = false
      ci     = true
    }
    shared-services = {
      id     = "555555555555"
      ou     = "Infrastructure"
      env    = "global"
      create = false
      ci     = true
    }
  }
}
"""


def make_root(*folders: str) -> Path:
    root = Path(tempfile.mkdtemp())
    for folder in folders:
        (root / folder).mkdir(parents=True)
    return root


class ParseRegistry(unittest.TestCase):
    def test_reads_every_account_and_field(self):
        accounts = gam.parse_registry(REGISTRY)
        self.assertEqual(len(accounts), 7)
        self.assertEqual(accounts["workloads-dev"]["id"], "222222222222")
        self.assertEqual(accounts["management"]["ci"], "true")  # a trailing comment is ignored
        self.assertEqual(accounts["workloads-staging"]["ci"], "false")


class BuildMatrix(unittest.TestCase):
    def setUp(self):
        self.root = make_root(
            "foundation-live-repo/management",
            "foundation-live-repo/log-archive",
            "workloads-live-repo/workloads-dev",
            "workloads-live-repo/workloads-prod",
            "workloads-live-repo/workloads-staging",
            "foundation-live-repo/network-hub",
        )
        self.entries, self.notices = gam.build_matrix(REGISTRY, self.root)

    def test_apply_order_is_management_core_dev_prod(self):
        self.assertEqual([e["account"] for e in self.entries], ["management", "log-archive", "workloads-dev", "workloads-prod"])

    def test_role_arns_come_from_the_account_id(self):
        dev = next(e for e in self.entries if e["account"] == "workloads-dev")
        self.assertEqual(dev["plan_role_arn"], "arn:aws:iam::222222222222:role/github-actions-plan")
        self.assertEqual(dev["apply_role_arn"], "arn:aws:iam::222222222222:role/github-actions-apply")

    def test_github_environment_per_account(self):
        envs = {e["account"]: e["github_environment"] for e in self.entries}
        self.assertEqual(envs, {"management": "management", "log-archive": "core", "workloads-dev": "dev", "workloads-prod": "prod"})

    def test_working_directory_points_into_the_right_repo(self):
        wd = {e["account"]: e["working_directory"] for e in self.entries}
        self.assertEqual(wd["management"], "foundation-live-repo/management")
        self.assertEqual(wd["workloads-dev"], "workloads-live-repo/workloads-dev")

    def test_working_directory_resolves_ou_nested_folders(self):
        root = make_root(
            "foundation-live-repo/management",
            "foundation-live-repo/security/log-archive",
            "workloads-live-repo/workloads/nonprod/workloads-dev",
        )
        entries, _ = gam.build_matrix(REGISTRY, root)
        wd = {e["account"]: e["working_directory"] for e in entries}
        self.assertEqual(wd["log-archive"], "foundation-live-repo/security/log-archive")
        self.assertEqual(wd["workloads-dev"], "workloads-live-repo/workloads/nonprod/workloads-dev")

    def test_ci_false_is_not_run_and_not_reported(self):
        self.assertNotIn("workloads-staging", [e["account"] for e in self.entries])
        self.assertFalse(any("workloads-staging" in n for n in self.notices))

    def test_placeholder_id_is_skipped_with_a_reason(self):
        self.assertNotIn("network-hub", [e["account"] for e in self.entries])
        self.assertTrue(any("network-hub" in n and "placeholder" in n for n in self.notices))

    def test_missing_live_folder_is_skipped_with_a_reason(self):
        self.assertNotIn("shared-services", [e["account"] for e in self.entries])
        self.assertTrue(any("shared-services" in n and "no live folder" in n for n in self.notices))


class Cli(unittest.TestCase):
    def test_github_output_and_single_account(self):
        root = make_root("workloads-live-repo/workloads-dev")
        entries, _ = gam.build_matrix(REGISTRY, root)
        self.assertEqual(len(entries), 1)
        with tempfile.NamedTemporaryFile("r", delete=False) as out:
            os.environ["GITHUB_OUTPUT"] = out.name
            gam.write_github_output({"matrix": json.dumps({"include": entries}), "count": str(len(entries))})
            content = Path(out.name).read_text()
        self.assertIn("count=1", content)
        self.assertIn('"account": "workloads-dev"', content)

    def test_empty_matrix_has_count_zero(self):
        entries, notices = gam.build_matrix(REGISTRY, make_root())
        self.assertEqual(entries, [])
        self.assertTrue(notices)  # every ci = true account explains why it was skipped


if __name__ == "__main__":
    unittest.main()
