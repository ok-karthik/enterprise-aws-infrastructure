import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cost_gate as g  # noqa: E402

FIX = Path(__file__).resolve().parent / "fixtures"


def load(name):
    return json.loads((FIX / name).read_text())


def ev(data):
    return g.evaluate(data, 100, 10, 20)


def run(path, *extra):
    return g.main([str(path), *extra])


class CostGate(unittest.TestCase):
    def test_large_increase_breaches(self):
        v = ev(load("infracost_increase_large.json"))
        self.assertTrue(v.breached)
        self.assertEqual(v.diff, 150.0)

    def test_percent_rule_breaches(self):
        v = ev(load("infracost_increase_pct.json"))
        self.assertTrue(v.breached)
        self.assertAlmostEqual(v.pct, 37.5)

    def test_small_sandbox_passes_because_of_the_floor(self):
        self.assertFalse(ev(load("infracost_small_sandbox.json")).breached)

    def test_null_passes_with_diff_zero(self):
        v = ev(load("infracost_null.json"))
        self.assertFalse(v.breached)
        self.assertEqual(v.diff, 0.0)

    def test_decrease_passes(self):
        v = ev(load("infracost_decrease.json"))
        self.assertFalse(v.breached)
        self.assertLess(v.diff, 0)

    def test_new_stack_over_max_breaches(self):
        v = ev({"pastTotalMonthlyCost": "0", "totalMonthlyCost": "150"})
        self.assertTrue(v.breached)
        self.assertIsNone(v.pct)

    def test_new_stack_under_max_passes(self):
        self.assertFalse(ev({"pastTotalMonthlyCost": "0", "totalMonthlyCost": "50"}).breached)

    def test_json_numbers_work(self):
        v = ev({"pastTotalMonthlyCost": 50, "totalMonthlyCost": 200.5, "diffTotalMonthlyCost": 150.5})
        self.assertTrue(v.breached)

    def test_missing_diff_is_total_minus_past(self):
        self.assertEqual(ev({"pastTotalMonthlyCost": "10", "totalMonthlyCost": "30"}).diff, 20.0)

    def test_bad_value_type_raises(self):
        with self.assertRaises(ValueError):
            g.to_float([1])

    def test_top_projects_sorted_descending(self):
        top = g.top_projects(load("infracost_increase_large.json"))
        self.assertEqual(top[0], ("dev/compute/eks", 120.0))
        self.assertEqual(len(top), 2)

    def test_breach_without_label_exits_1(self):
        self.assertEqual(run(FIX / "infracost_increase_large.json", "--labels", "foo"), 1)

    def test_label_approves_and_says_so(self):
        with tempfile.TemporaryDirectory() as d:
            md = Path(d) / "out.md"
            self.assertEqual(run(FIX / "infracost_increase_large.json", "--labels", "foo,cost-approved", "--markdown-out", str(md)), 0)
            self.assertIn("approved by label", md.read_text())

    def test_other_label_does_not_approve(self):
        self.assertEqual(run(FIX / "infracost_increase_large.json", "--labels", "cost-ok"), 1)

    def test_pass_exits_0(self):
        self.assertEqual(run(FIX / "infracost_small_sandbox.json"), 0)

    def test_missing_file_exits_2(self):
        self.assertEqual(run("/nonexistent/infracost.json"), 2)

    def test_not_json_exits_2(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.json"
            p.write_text("not json")
            self.assertEqual(run(p), 2)

    def test_unexpected_shape_exits_2_not_1(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.json"
            p.write_text('{"projects":[{"name":"x","diff":"5"}]}')
            self.assertEqual(run(p), 2)

    def test_markdown_is_appended_not_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            md = Path(d) / "out.md"
            md.write_text("existing\n")
            run(FIX / "infracost_increase_large.json", "--markdown-out", str(md))
            text = md.read_text()
            self.assertTrue(text.startswith("existing\n"))
            self.assertIn("Cost gate", text)


if __name__ == "__main__":
    unittest.main()
