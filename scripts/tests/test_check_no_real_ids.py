"""check_no_real_ids.py: a real id from accounts.local.hcl in a tracked file fails; output is masked."""
import contextlib
import importlib.util
import io
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "check_no_real_ids.py"
spec = importlib.util.spec_from_file_location("check_no_real_ids", SCRIPT)
cn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cn)

FAKE_REAL = "111222333444"
LOCAL = f"""
locals {{
  accounts = {{
    management = {{
      id = "954171757349"
    }}
    dev = {{
      id = "{FAKE_REAL}"
    }}
  }}
}}
"""


class NoRealIds(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        (self.root / "iac-live-repo/_config").mkdir(parents=True)

    def track(self, name: str, text: str) -> None:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        subprocess.run(["git", "add", "-f", name], cwd=self.root, check=True)

    def run_main(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cn.main([], self.root)
        return code, out.getvalue(), err.getvalue()

    def test_missing_local_file_passes_with_a_note(self):
        self.track("a.md", f"id {FAKE_REAL}\n")
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("nothing to check", out)

    def test_clean_repo_passes(self):
        (self.root / "iac-live-repo/_config/accounts.local.hcl").write_text(LOCAL)
        self.track("a.md", "fake 777777777777 and public 954171757349\n")
        self.assertEqual(self.run_main()[0], 0)

    def test_leak_fails_and_is_masked(self):
        (self.root / "iac-live-repo/_config/accounts.local.hcl").write_text(LOCAL)
        self.track("docs/x.md", f"ok\narn:aws:iam::{FAKE_REAL}:root\n")
        code, out, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("docs/x.md:2", err)
        self.assertIn("111***", err)
        self.assertNotIn(FAKE_REAL, out + err)

    def test_the_untracked_local_file_is_not_scanned(self):
        (self.root / "iac-live-repo/_config/accounts.local.hcl").write_text(LOCAL)
        self.track("a.md", "nothing\n")
        self.assertEqual(self.run_main()[0], 0)

    def test_longer_digit_runs_are_not_matches(self):
        (self.root / "iac-live-repo/_config/accounts.local.hcl").write_text(LOCAL)
        self.track("a.md", f"9{FAKE_REAL}9\n")
        self.assertEqual(self.run_main()[0], 0)


if __name__ == "__main__":
    unittest.main()
