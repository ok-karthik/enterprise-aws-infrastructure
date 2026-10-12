"""org_tree.py: the OU tree text, the README block and the staleness check (no AWS access)."""
import importlib.util
import re
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "org_tree.py"
spec = importlib.util.spec_from_file_location("org_tree", SCRIPT)
ot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ot)

REGISTRY = """
locals {
  accounts = {
    management = {
      id = "954171757349"
      ou = "Root"
    }
    log-archive = {
      id = "000000000001"
      ou = "Security"
    }
    workloads-dev = {
      id = "777777777777"
      ou = "NonProd"
    }
  }
}
"""
ORGANIZATION = """
locals {
  organizational_units = {
    "Security"  = {}
    "Workloads" = {}
    "NonProd"   = { parent = "Workloads" }
    "Sandbox"   = {}
  }
}
"""
README = "# Live\n\n<!-- org-tree:start -->\nold\n<!-- org-tree:end -->\n\nrest\n"


def make_root(readme: str = README) -> Path:
    root = Path(tempfile.mkdtemp())
    config = root / "iac-live-repo" / "_config"
    config.mkdir(parents=True)
    (config / "accounts.hcl").write_text(REGISTRY)
    (config / "organization.hcl").write_text(ORGANIZATION)
    (root / "iac-live-repo" / "README.md").write_text(readme)
    (root / "iac-live-repo" / "root" / "management").mkdir(parents=True)
    (root / "iac-live-repo" / "workloads" / "nonprod" / "workloads-dev").mkdir(parents=True)
    return root


class Tree(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.accounts = ot.parse_registry(REGISTRY)
        self.ous = ot.parse_ous(ORGANIZATION)

    def test_tree_has_every_ou_including_empty_ones_and_the_folders(self):
        text = ot.render_tree(self.accounts, self.ous, self.root, show_ids=True)
        lines = text.splitlines()
        self.assertEqual(lines[0], "Root")
        self.assertIn("management", lines[1])
        self.assertIn("954171757349", lines[1])
        self.assertIn("iac-live-repo/root/management", lines[1])
        self.assertTrue(lines[2].endswith("Security"))
        self.assertIn("log-archive", lines[3])
        self.assertIn("placeholder", lines[3])
        self.assertIn("iac-live-repo/security/log-archive  (no live folder)", lines[3])
        self.assertTrue(any(l.endswith("NonProd") for l in lines))
        self.assertIn("iac-live-repo/workloads/nonprod/workloads-dev", text)
        self.assertTrue(lines[-1].endswith("Sandbox  (no accounts)"), lines[-1])

    def test_readme_mode_hides_the_ids(self):
        text = ot.render_tree(self.accounts, self.ous, self.root, show_ids=False)
        self.assertNotRegex(text, r"\d{12}")
        self.assertIn("real", text)
        self.assertIn("placeholder", text)


class ReadmeBlock(unittest.TestCase):
    def test_check_fails_when_stale_and_passes_after_readme(self):
        root = make_root()
        self.assertEqual(ot.main(["--check"], root), 1)
        self.assertEqual(ot.main(["--readme"], root), 0)
        self.assertEqual(ot.main(["--check"], root), 0)
        text = (root / "iac-live-repo/README.md").read_text()
        self.assertTrue(text.startswith("# Live\n"))
        self.assertTrue(text.endswith("\nrest\n"))

    def test_the_block_never_contains_a_12_digit_id(self):
        root = make_root()
        ot.main(["--readme"], root)
        text = (root / "iac-live-repo/README.md").read_text()
        self.assertIsNone(re.search(r"\d{12}", text))

    def test_a_changed_registry_makes_the_block_stale(self):
        root = make_root()
        ot.main(["--readme"], root)
        registry = root / "iac-live-repo/_config/accounts.hcl"
        registry.write_text(REGISTRY.replace('ou = "NonProd"', 'ou = "Sandbox"'))
        self.assertEqual(ot.main(["--check"], root), 1)

    def test_a_readme_without_the_markers_fails(self):
        root = make_root("# Live\n")
        self.assertEqual(ot.main(["--check"], root), 1)


if __name__ == "__main__":
    unittest.main()
