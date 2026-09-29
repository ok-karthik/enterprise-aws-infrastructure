import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_policy_catalog as c  # noqa: E402


class PolicyCatalog(unittest.TestCase):
    def test_helpers_and_tests_are_not_rules(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ["a.rego", "a_test.rego", "helpers.rego", "notes.md"]:
                (Path(d) / name).write_text("")
            self.assertEqual(c.rule_files(Path(d)), ["a.rego"])

    def test_unlisted_rule_is_reported(self):
        self.assertEqual(c.unlisted("| x | `a.rego` |", ["a.rego", "b.rego"]), ["b.rego"])

    def test_the_real_catalog_is_complete(self):
        self.assertEqual(c.unlisted(c.CATALOG.read_text(encoding="utf-8"), c.rule_files()), [])


if __name__ == "__main__":
    unittest.main()
