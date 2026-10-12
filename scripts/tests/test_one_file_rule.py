"""The one-file rule: a stack (terragrunt.hcl) must not look anything up itself. check-account-registry.sh enforces it."""
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "check-account-registry.sh"

REGISTRY = """
locals {
  accounts = {
    workloads-dev = {
      id  = "000000000005"
      ou  = "NonProd"
      env = "dev"
    }
    management = {
      id  = "000000000000"
      ou  = "Root"
      env = "global"
    }
  }
}
"""
REGIONS = """
locals {
  primary_region   = "eu-central-1"
  secondary_region = "eu-west-1"
  allowed_regions_by_ou = {
    NonProd = ["eu-central-1"]
  }
}
"""
ORGANIZATION = """
locals {
  organizational_units = {
    "Security"       = {}
    "Workloads"      = {}
    "Prod"           = { parent = "Workloads" }
    "NonProd"        = { parent = "Workloads" }
  }
}
"""
CLEAN = """include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/iac-modules-repo/network/vpc"
}

inputs = {
  name = include.root.locals.account_name
}
"""


def make_tree(leaf_text: str, leaf: str = "workloads/nonprod/workloads-dev/eu-central-1/vpc") -> Path:
    root = Path(tempfile.mkdtemp())
    config = root / "iac-live-repo" / "_config"
    config.mkdir(parents=True)
    (config / "accounts.hcl").write_text(REGISTRY)
    (config / "regions.hcl").write_text(REGIONS)
    (config / "organization.hcl").write_text(ORGANIZATION)
    stack = root / "iac-live-repo" / leaf
    stack.mkdir(parents=True)
    (stack / "terragrunt.hcl").write_text(leaf_text)
    return root


def run(root: Path) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(SCRIPT), str(root)], capture_output=True, text=True)


class OneFileRule(unittest.TestCase):
    def test_a_clean_stack_passes(self):
        r = run(make_tree(CLEAN))
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_read_terragrunt_config_fails(self):
        r = run(make_tree(CLEAN + '\nlocals {\n  x = read_terragrunt_config("a.hcl")\n}\n'))
        self.assertEqual(r.returncode, 1)
        self.assertIn("read_terragrunt_config", r.stderr)

    def test_get_env_fails(self):
        r = run(make_tree(CLEAN + '\nlocals {\n  x = get_env("A", "")\n}\n'))
        self.assertEqual(r.returncode, 1)
        self.assertIn("get_env(", r.stderr)

    def test_another_find_in_parent_folders_fails(self):
        r = run(make_tree(CLEAN + '\nlocals {\n  x = find_in_parent_folders("other.hcl")\n}\n'))
        self.assertEqual(r.returncode, 1)
        self.assertIn("find_in_parent_folders", r.stderr)

    def test_a_folder_that_is_not_in_the_registry_fails(self):
        r = run(make_tree(CLEAN, leaf="not-an-account/eu-central-1/vpc"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("not-an-account", r.stderr)

    def test_a_region_not_allowed_for_the_ou_fails(self):
        r = run(make_tree(CLEAN, leaf="workloads/nonprod/workloads-dev/eu-west-1/vpc"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("eu-west-1", r.stderr)

    def test_a_nested_ou_folder_passes(self):
        r = run(make_tree(CLEAN, leaf="workloads/nonprod/workloads-dev/eu-central-1/vpc"))
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_the_management_account_under_root_passes(self):
        r = run(make_tree(CLEAN, leaf="root/management/eu-central-1/budgets"))
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_an_account_in_the_wrong_ou_folder_fails(self):
        r = run(make_tree(CLEAN, leaf="workloads/prod/workloads-dev/eu-central-1/vpc"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("account 'workloads-dev' is in OU 'NonProd' (registry), so its folder must be iac-live-repo/workloads/nonprod/workloads-dev", r.stderr)

    def test_an_account_at_the_top_level_fails(self):
        r = run(make_tree(CLEAN, leaf="workloads-dev/eu-central-1/vpc"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("must be iac-live-repo/workloads/nonprod/workloads-dev", r.stderr)

    def test_a_stray_folder_under_an_ou_folder_fails(self):
        root = make_tree(CLEAN)
        (root / "iac-live-repo" / "workloads" / "nonprod" / "stray").mkdir()
        r = run(root)
        self.assertEqual(r.returncode, 1)
        self.assertIn("workloads/nonprod/stray", r.stderr)

    def test_a_stack_at_the_wrong_depth_fails(self):
        r = run(make_tree(CLEAN, leaf="workloads/nonprod/workloads-dev/eu-central-1/vpc/extra"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("a stack must be", r.stderr)


if __name__ == "__main__":
    unittest.main()
