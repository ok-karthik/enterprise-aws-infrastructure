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


OUS = {
    "Security": None,
    "Infrastructure": None,
    "Workloads": None,
    "Prod": "Workloads",
    "NonProd": "Workloads",
}


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
            "iac-live-repo/root/management",
            "iac-live-repo/security/log-archive",
            "iac-live-repo/workloads/nonprod/workloads-dev",
            "iac-live-repo/workloads/prod/workloads-prod",
            "iac-live-repo/workloads/nonprod/workloads-staging",
            "iac-live-repo/infrastructure/network-hub",
        )
        self.entries, self.notices = gam.build_matrix(REGISTRY, self.root, OUS)

    def test_apply_order_is_management_core_dev_prod(self):
        self.assertEqual([e["account"] for e in self.entries], ["management", "log-archive", "workloads-dev", "workloads-prod"])

    def test_role_arns_come_from_the_account_id(self):
        dev = next(e for e in self.entries if e["account"] == "workloads-dev")
        self.assertEqual(dev["plan_role_arn"], "arn:aws:iam::222222222222:role/github-actions-plan")
        self.assertEqual(dev["apply_role_arn"], "arn:aws:iam::222222222222:role/github-actions-apply")

    def test_github_environment_per_account(self):
        envs = {e["account"]: e["github_environment"] for e in self.entries}
        self.assertEqual(envs, {"management": "management", "log-archive": "core", "workloads-dev": "dev", "workloads-prod": "prod"})

    def test_working_directory_is_the_ou_path_and_account_folder(self):
        wd = {e["account"]: e["working_directory"] for e in self.entries}
        self.assertEqual(wd["management"], "iac-live-repo/root/management")
        self.assertEqual(wd["log-archive"], "iac-live-repo/security/log-archive")
        self.assertEqual(wd["workloads-dev"], "iac-live-repo/workloads/nonprod/workloads-dev")
        self.assertEqual(wd["workloads-prod"], "iac-live-repo/workloads/prod/workloads-prod")

    def test_a_folder_that_is_not_in_the_registry_is_not_matched(self):
        root = make_root("iac-live-repo/root/management", "iac-live-repo/not-an-account", "iac-live-repo/nonprod/workloads-dev")
        entries, notices = gam.build_matrix(REGISTRY, root, OUS)
        self.assertEqual([e["account"] for e in entries], ["management"])
        self.assertTrue(any("workloads-dev" in n and "no live folder" in n for n in notices))

    def test_ci_false_is_not_run_and_not_reported(self):
        self.assertNotIn("workloads-staging", [e["account"] for e in self.entries])
        self.assertFalse(any("workloads-staging" in n for n in self.notices))

    def test_placeholder_id_is_skipped_with_a_reason(self):
        self.assertNotIn("network-hub", [e["account"] for e in self.entries])
        self.assertTrue(any("network-hub" in n and "placeholder" in n for n in self.notices))

    def test_missing_live_folder_is_skipped_with_a_reason(self):
        self.assertNotIn("shared-services", [e["account"] for e in self.entries])
        self.assertTrue(any("shared-services" in n and "no live folder" in n for n in self.notices))


LOCAL_FILE = """
locals {
  accounts = {
    workloads-dev = {
      id = "888888888888"
    }
  }
}
"""

BASE = """
locals {
  accounts = {
    workloads-dev = {
      id = "000000000002"
      ou = "NonProd"
      env = "dev"
      ci = true
    }
  }
}
"""


class LocalRegistry(unittest.TestCase):
    """Real ids come from accounts.local.hcl, or from $ACCOUNTS_LOCAL_HCL when that file does not exist."""

    def setUp(self):
        self.root = make_root("iac-live-repo/workloads/nonprod/workloads-dev")
        self.saved = os.environ.pop("ACCOUNTS_LOCAL_HCL", None)

    def tearDown(self):
        os.environ.pop("ACCOUNTS_LOCAL_HCL", None)
        if self.saved is not None:
            os.environ["ACCOUNTS_LOCAL_HCL"] = self.saved

    def write_local_file(self, text):
        path = self.root / gam.LOCAL_REGISTRY
        path.parent.mkdir(parents=True)
        path.write_text(text, encoding="utf-8")

    def test_local_file_present(self):
        self.write_local_file(LOCAL_FILE)
        entries, _ = gam.build_matrix(BASE, self.root, OUS)
        self.assertEqual([e["account_id"] for e in entries], ["888888888888"])

    def test_env_only(self):
        os.environ["ACCOUNTS_LOCAL_HCL"] = LOCAL_FILE
        entries, _ = gam.build_matrix(BASE, self.root, OUS)
        self.assertEqual([e["account_id"] for e in entries], ["888888888888"])

    def test_file_wins_over_env(self):
        self.write_local_file(LOCAL_FILE)
        os.environ["ACCOUNTS_LOCAL_HCL"] = LOCAL_FILE.replace("888888888888", "777777777777")
        entries, _ = gam.build_matrix(BASE, self.root, OUS)
        self.assertEqual([e["account_id"] for e in entries], ["888888888888"])

    def test_neither_keeps_the_placeholder_and_skips_with_a_notice(self):
        entries, notices = gam.build_matrix(BASE, self.root, OUS)
        self.assertEqual(entries, [])
        self.assertEqual(len(notices), 1)
        self.assertIn("placeholder", notices[0])

    def test_empty_env_is_the_same_as_unset(self):
        os.environ["ACCOUNTS_LOCAL_HCL"] = "  \n"
        entries, notices = gam.build_matrix(BASE, self.root, OUS)
        self.assertEqual(entries, [])
        self.assertEqual(len(notices), 1)


class Cli(unittest.TestCase):
    def test_github_output_and_single_account(self):
        root = make_root("iac-live-repo/workloads/nonprod/workloads-dev")
        entries, _ = gam.build_matrix(REGISTRY, root, OUS)
        self.assertEqual(len(entries), 1)
        with tempfile.NamedTemporaryFile("r", delete=False) as out:
            os.environ["GITHUB_OUTPUT"] = out.name
            gam.write_github_output({"matrix": json.dumps({"include": entries}), "count": str(len(entries))})
            content = Path(out.name).read_text()
        self.assertIn("count=1", content)
        self.assertIn('"account": "workloads-dev"', content)

    def test_empty_matrix_has_count_zero(self):
        entries, notices = gam.build_matrix(REGISTRY, make_root(), OUS)
        self.assertEqual(entries, [])
        self.assertTrue(notices)  # every ci = true account explains why it was skipped


class PerRegion(unittest.TestCase):
    def test_one_entry_per_account_and_region_folder(self):
        base = "iac-live-repo/root/management"
        root = make_root(f"{base}/_global/organization", f"{base}/eu-central-1/budgets", f"{base}/notes")
        for stack in ["_global/organization", "eu-central-1/budgets"]:
            (root / base / stack / "terragrunt.hcl").write_text("")
        entries, _ = gam.build_matrix(REGISTRY, root, OUS)
        expanded, notices = gam.expand_per_region(entries, root)
        # The key stays <account>/<region> (it names the drift issue); only the working directory carries the OU path.
        self.assertEqual([e["key"] for e in expanded], ["management/_global", "management/eu-central-1"])
        self.assertEqual(expanded[1]["working_directory"], "iac-live-repo/root/management/eu-central-1")
        self.assertEqual(expanded[1]["account"], "management")
        self.assertEqual(notices, [])

    def test_an_account_without_region_folders_is_reported_not_failed(self):
        root = make_root("iac-live-repo/root/management")
        entries, _ = gam.build_matrix(REGISTRY, root, OUS)
        expanded, notices = gam.expand_per_region(entries, root)
        self.assertEqual(expanded, [])
        self.assertIn("management", notices[0])


ORGANIZATION = """
locals {
  organizational_units = {
    "Security"       = {}
    "Workloads"      = {}
    "Prod"           = { parent = "Workloads" }
    "NonProd"        = { parent = "Workloads" }
    "Policy-Staging" = {}
  }
}
"""


class OuFolders(unittest.TestCase):
    def test_parse_ous_keeps_file_order_and_parents(self):
        self.assertEqual(
            gam.parse_ous(ORGANIZATION),
            {"Security": None, "Workloads": None, "Prod": "Workloads", "NonProd": "Workloads", "Policy-Staging": None},
        )

    def test_ou_folder(self):
        ous = gam.parse_ous(ORGANIZATION)
        self.assertEqual(gam.ou_folder("Root", ous), "root")
        self.assertEqual(gam.ou_folder("Security", ous), "security")
        self.assertEqual(gam.ou_folder("NonProd", ous), "workloads/nonprod")
        self.assertEqual(gam.ou_folder("Policy-Staging", ous), "policy-staging")

    def test_the_real_organization_file_parses_to_the_eight_ous(self):
        text = (gam.REPO_ROOT / gam.ORGANIZATION).read_text(encoding="utf-8")
        self.assertEqual(
            list(gam.parse_ous(text)),
            ["Security", "Infrastructure", "Workloads", "Prod", "NonProd", "Sandbox", "Policy-Staging", "Suspended"],
        )

    def test_find_account_dir_follows_the_registry_ou(self):
        root = make_root("iac-live-repo/workloads/nonprod/workloads-dev", "iac-live-repo/workloads/prod/workloads-dev")
        found = gam.find_account_dir(root, "workloads-dev", "NonProd", OUS)
        self.assertEqual(found, root / "iac-live-repo/workloads/nonprod/workloads-dev")
        self.assertIsNone(gam.find_account_dir(root, "workloads-dev", "Infrastructure", OUS))


if __name__ == "__main__":
    unittest.main()
