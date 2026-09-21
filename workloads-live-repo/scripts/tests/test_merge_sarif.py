"""Unit tests for merge_sarif.py (no network, no Checkov needed)."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "merge_sarif.py"
spec = importlib.util.spec_from_file_location("merge_sarif", SCRIPT)
ms = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ms)


def result(rule="CKV_AWS_24", uri="plans/a/tfplan.json", line=1, text="open ssh"):
    return {"ruleId": rule, "message": {"text": text}, "locations": [{"physicalLocation": {"artifactLocation": {"uri": uri}, "region": {"startLine": line}}}]}


def doc(results, rules=("CKV_AWS_24",)):
    return {"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "Checkov", "rules": [{"id": r} for r in rules]}}, "results": results}]}


class Merge(unittest.TestCase):
    def test_findings_from_several_plans_end_up_in_one_run(self):
        merged = ms.merge([doc([result(uri="plans/a/tfplan.json")]), doc([result(uri="plans/b/tfplan.json")])])
        self.assertEqual(len(merged["runs"]), 1)
        self.assertEqual(len(merged["runs"][0]["results"]), 2)

    def test_duplicates_from_the_config_directories_are_dropped(self):
        same = result()
        merged = ms.merge([doc([same, dict(same), dict(same), dict(same)])])
        self.assertEqual(len(merged["runs"][0]["results"]), 1)

    def test_same_rule_in_two_plans_is_two_findings(self):
        merged = ms.merge([doc([result(uri="plans/a/tfplan.json")]), doc([result(uri="plans/b/tfplan.json")])])
        self.assertEqual({r["locations"][0]["physicalLocation"]["artifactLocation"]["uri"] for r in merged["runs"][0]["results"]}, {"plans/a/tfplan.json", "plans/b/tfplan.json"})

    def test_rules_are_listed_once(self):
        merged = ms.merge([doc([result()], rules=("CKV_AWS_24", "CKV_AWS_25")), doc([result(uri="x")], rules=("CKV_AWS_24",))])
        self.assertEqual(sorted(r["id"] for r in merged["runs"][0]["tool"]["driver"]["rules"]), ["CKV_AWS_24", "CKV_AWS_25"])

    def test_nothing_to_merge_gives_an_empty_valid_run(self):
        merged = ms.merge([])
        self.assertEqual(merged["runs"][0]["results"], [])
        self.assertEqual(merged["version"], "2.1.0")


class Cli(unittest.TestCase):
    def test_reads_a_directory_and_writes_one_file(self):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "in").mkdir()
        (tmp / "in" / "1").write_text(json.dumps(doc([result(uri="a")])))
        (tmp / "in" / "2").write_text(json.dumps(doc([result(uri="b"), result(uri="b")])))
        out = tmp / "out.sarif"
        self.assertEqual(ms.main(["merge_sarif.py", str(tmp / "in"), str(out)]), 0)
        self.assertEqual(len(json.loads(out.read_text())["runs"][0]["results"]), 2)

    def test_unreadable_input_fails_loudly(self):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "bad").write_text("not json")
        self.assertEqual(ms.main(["merge_sarif.py", str(tmp / "bad"), str(tmp / "out.sarif")]), 1)


if __name__ == "__main__":
    unittest.main()
