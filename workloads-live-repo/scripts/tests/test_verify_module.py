"""Offline tests for verify_module.py: the parsers and the output format (no terraform, no AWS)."""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_module as vm  # noqa: E402

MODULE = Path("/repo/iac-modules-repo/storage/s3")


class Parsers(unittest.TestCase):
    def test_fmt_lists_files(self):
        out = vm.parse_fmt(f"{MODULE}/main.tf\n{MODULE}/variables.tf\n", MODULE)
        self.assertEqual([f.line_text() for f in out], ["terraform-fmt FMT main.tf:1", "terraform-fmt FMT variables.tf:1"])

    def test_validate_keeps_only_errors_with_their_line(self):
        data = {"diagnostics": [
            {"severity": "error", "summary": "Unsupported argument", "range": {"filename": "main.tf", "start": {"line": 12}}},
            {"severity": "warning", "summary": "Deprecated", "range": {"filename": "main.tf", "start": {"line": 3}}},
        ]}
        out = vm.parse_validate(json.dumps(data), MODULE)
        self.assertEqual([f.line_text() for f in out], ["terraform-validate VALIDATE main.tf:12"])

    def test_tflint(self):
        data = {"issues": [{"rule": {"name": "terraform_unused_declarations"}, "message": "x", "range": {"filename": "variables.tf", "start": {"line": 7}}}], "errors": []}
        self.assertEqual(vm.parse_tflint(json.dumps(data), MODULE)[0].line_text(), "tflint terraform_unused_declarations variables.tf:7")

    def test_checkov_json_object_and_list_and_concatenated(self):
        obj = {"results": {"failed_checks": [{"check_id": "CKV_AWS_53", "file_path": "/main.tf", "file_line_range": [49, 56], "check_name": "Ensure S3 bucket has block public ACLS enabled"}]}}
        expected = ["checkov CKV_AWS_53 main.tf:49"]
        self.assertEqual([f.line_text() for f in vm.parse_checkov(json.dumps(obj), MODULE)], expected)
        self.assertEqual([f.line_text() for f in vm.parse_checkov(json.dumps([obj]), MODULE)], expected)
        two = json.dumps({"results": {"failed_checks": []}}) + "\n" + json.dumps(obj)
        self.assertEqual([f.line_text() for f in vm.parse_checkov(two, MODULE)], expected)

    def test_terraform_test_failures_name_the_run_and_the_file(self):
        text = 'tests/s3.tftest.hcl... in progress\n  run "a"... pass\n  run "guardrails_stay_on"... fail\n  run "c"... skip\n'
        self.assertEqual([f.line_text() for f in vm.parse_terraform_test(text, MODULE)], ["terraform-test guardrails_stay_on tests/s3.tftest.hcl:1"])

    def test_conftest(self):
        data = [{"failures": [{"msg": "Governance Violation: x", "metadata": {"query": "data.main.deny"}}]}]
        self.assertEqual(vm.parse_conftest(json.dumps(data), MODULE)[0].tool, "conftest")

    def test_bad_json_never_raises(self):
        for parser in (vm.parse_validate, vm.parse_tflint, vm.parse_checkov, vm.parse_conftest):
            self.assertEqual(parser("not json", MODULE), [])


class Output(unittest.TestCase):
    def test_failure_lines_come_first_then_one_status_per_step_and_skips_are_visible(self):
        results = [
            vm.StepResult("fmt", "PASS"),
            vm.StepResult("checkov", "FAIL", findings=[vm.Finding("checkov", "CKV_AWS_53", "main.tf", 49)]),
            vm.StepResult("conftest", "SKIPPED", "no examples/basic"),
        ]
        text = vm.render("storage/s3", results)
        lines = text.splitlines()
        self.assertEqual(lines[0], "checkov CKV_AWS_53 main.tf:49")
        self.assertIn("[SKIPPED] conftest (no examples/basic)", lines)
        self.assertEqual(lines[-1], "storage/s3: FAILED: checkov | SKIPPED: conftest")

    def test_a_clean_run_says_ok(self):
        self.assertEqual(vm.render("m", [vm.StepResult("fmt", "PASS")]).splitlines()[-1], "m: ok")

    def test_not_a_module_exits_2(self):
        self.assertEqual(vm.main(["nope/nothing"]), 2)

    def test_fake_keys_are_not_in_any_scanned_file(self):
        # They live in the child environment only. A hard-coded key in HCL would fail Checkov (CKV_AWS_41).
        text = "".join(p.read_text() for p in Path(vm.REPO_ROOT, "iac-modules-repo").glob("*/*/examples/basic/*.tf"))
        self.assertNotIn(vm.FAKE_ENV["AWS_ACCESS_KEY_ID"], text)


if __name__ == "__main__":
    unittest.main()
