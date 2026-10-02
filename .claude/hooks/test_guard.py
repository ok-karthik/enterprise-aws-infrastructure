#!/usr/bin/env python3
"""Tests for the local-agent guardrails (PLAN 11.2): every blocked command and path is blocked, read-only ones are not,
and the attempt counter stops at N. Offline: verify_module is patched, nothing is run."""

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import guard  # noqa: E402


def run_hook(mode: str, payload: dict) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with mock.patch("sys.stdin", io.StringIO(json.dumps(payload))), redirect_stdout(out), redirect_stderr(err):
        code = guard.main(["guard.py", mode])
    return code, out.getvalue(), err.getvalue()


def bash(command: str) -> int:
    return run_hook("pre-bash", {"tool_name": "Bash", "tool_input": {"command": command}})[0]


class BlockedCommands(unittest.TestCase):
    def test_apply_destroy_and_state_edits_are_blocked_however_they_are_spelled(self):
        for command in [
            "terraform apply",
            "terraform apply -auto-approve",
            "terragrunt apply",
            "terragrunt run apply",
            "terragrunt run --all apply",
            "terragrunt run --all --non-interactive -auto-approve apply",
            "terragrunt run -- apply",
            "terragrunt run-all apply",
            "terraform destroy",
            "terragrunt destroy --auto-approve",
            "terragrunt run --all destroy",
            "terraform state rm module.eks.aws_eks_cluster.this[0]",
            "terragrunt state mv a b",
            "terraform state push terraform.tfstate",
            "terraform force-unlock 1234",
            "terraform import aws_s3_bucket.b my-bucket",
            "tofu apply",
            "/opt/homebrew/bin/terraform apply",
        ]:
            self.assertEqual(bash(command), 2, command)

    def test_blocked_inside_chains_wrappers_and_shells(self):
        for command in [
            "cd workloads-live-repo/workloads/prod/workloads-prod && terragrunt apply",
            "cd x; terraform apply",
            "make plan || terraform apply",
            "echo done | terraform apply",
            "AWS_PROFILE=prod terraform apply",
            "TF_LOG=debug AWS_PROFILE=x terragrunt run --all apply",
            "sudo terraform apply",
            "env FOO=1 terraform destroy",
            "time terraform apply",
            "timeout 600 terraform apply",
            "nohup terragrunt apply &",
            "bash -c 'terraform apply'",
            'sh -c "cd x && terragrunt destroy"',
            'eval "terragrunt apply"',
            "echo x | xargs terraform apply",
            "(cd x && terraform apply)",
            "$(terraform apply)",
            "cd x\nterraform apply",
            "bash -c \"bash -c 'terraform apply'\"",
        ]:
            self.assertEqual(bash(command), 2, command)

    def test_run_all_without_a_read_only_command_is_blocked(self):
        for command in ["terragrunt run --all", "terragrunt run --all --non-interactive", "terragrunt --all"]:
            self.assertEqual(bash(command), 2, command)

    def test_make_apply_targets_are_blocked(self):
        for command in ["make apply", "make destroy ENV=prod", "make -C infra deploy", "make plan apply"]:
            self.assertEqual(bash(command), 2, command)

    def test_a_blocked_call_says_why_on_stderr(self):
        code, _, err = run_hook("pre-bash", {"tool_input": {"command": "terragrunt apply"}})
        self.assertEqual(code, 2)
        self.assertIn("agent guardrails", err)
        self.assertIn("apply", err)


class AllowedCommands(unittest.TestCase):
    def test_read_only_and_ordinary_commands_pass(self):
        for command in [
            "terraform plan",
            "terraform plan -out=tfplan.bin -lock=false",
            "terraform validate",
            "terraform fmt -check -recursive",
            "terraform init -backend=false",
            "terraform test",
            "terraform show -json tfplan.bin",
            "terragrunt plan",
            "terragrunt run --all plan",
            "terragrunt run --all --non-interactive --log-format bare plan",
            "terragrunt run --all validate",
            "terragrunt hcl fmt --check",
            "terragrunt render --format json",
            "terragrunt stack generate",
            "make plan ENV=nonprod/workloads-dev",
            "make verify-module MODULE=storage/s3",
            "make test",
            "cd iac-modules-repo/storage/s3 && terraform test",
            "git commit -m 'docs: explain why we never run terraform apply by hand'",
            "echo terraform apply is forbidden",
            "grep -rn 'terraform apply' docs",
            "python3 workloads-live-repo/scripts/verify_module.py storage/s3",
            "ls",
            "",
            'git commit -m "feat: make apply safer"',
            'git commit -m "docs: cd x && terraform apply"',
            "git commit -m 'docs: add blue-green runbook\n\nmake apply is covered in section 3'",
            'echo "cd x && terraform apply"',
            "cat << 'EOF' > scratch/notes.md\nHere is a note about policy-library-repo/terraform/require_tags.rego\nmake apply is noted\nEOF",
            "echo 'reference to .checkov.yaml' > scratch/notes.md",
        ]:
            self.assertEqual(bash(command), 0, command)


class ProtectedFiles(unittest.TestCase):
    def edit(self, path: str) -> int:
        return run_hook("pre-edit", {"tool_name": "Edit", "tool_input": {"file_path": path}})[0]

    def test_files_that_define_passing_are_blocked(self):
        root = guard.REPO_ROOT
        for path in [
            ".checkov.yaml",
            str(root / ".checkov.yaml"),
            ".trivyignore",
            "policy-library-repo/terraform/require_tags.rego",
            str(root / "policy-library-repo" / "POLICIES.md"),
            "iac-modules-repo/../policy-library-repo/terraform/helpers.rego",
            ".claude/settings.json",
            ".claude/hooks/guard.py",
        ]:
            self.assertEqual(self.edit(path), 2, path)

    def test_ordinary_files_are_not(self):
        root = guard.REPO_ROOT
        for path in ["iac-modules-repo/storage/s3/main.tf", str(root / "docs" / "SLO.md"), "README.md", ".github/workflows/terragrunt.yml"]:
            self.assertEqual(self.edit(path), 0, path)

    def test_shell_writes_to_protected_files_are_blocked(self):
        for command in [
            "sed -i '' 's/a/b/' .checkov.yaml",
            "echo x >> .checkov.yaml",
            "rm policy-library-repo/terraform/require_tags.rego",
            "git checkout -- .checkov.yaml",
            "cp foo.yaml .checkov.yaml",
            "mv foo.yaml .checkov.yaml",
            "truncate -s 0 .checkov.yaml",
            "cat << 'EOF' > .checkov.yaml\nchecks\nEOF",
            "python3 -c \"open('.checkov.yaml', 'w').write('')\"",
        ]:
            self.assertEqual(bash(command), 2, command)
        self.assertEqual(bash("cat .checkov.yaml"), 0)
        self.assertEqual(bash("git diff -- policy-library-repo"), 0)


class AttemptLimit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.patch_state = mock.patch.object(guard, "STATE_PATH", Path(self.tmp.name) / "verify_attempts.json")
        self.patch_state.start()
        self.path = "iac-modules-repo/storage/s3/main.tf"

    def tearDown(self):
        self.patch_state.stop()
        self.tmp.cleanup()

    def post_edit(self, ok: bool, summary: str = "checkov CKV_AWS_53 main.tf:49") -> tuple[int, str, str]:
        with mock.patch.object(guard, "run_verify", return_value=(ok, summary)):
            return run_hook("post-edit", {"tool_name": "Edit", "tool_input": {"file_path": self.path}})

    def test_edits_outside_a_module_are_ignored(self):
        with mock.patch.object(guard, "run_verify", side_effect=AssertionError("must not run")):
            self.assertEqual(run_hook("post-edit", {"tool_input": {"file_path": "docs/SLO.md"}})[0], 0)

    def test_the_summary_goes_back_to_the_agent(self):
        code, out, _ = self.post_edit(False)
        self.assertEqual(code, 0)
        context = json.loads(out)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("CKV_AWS_53", context)
        self.assertIn("FAILED", context)

    def test_stops_after_n_failures_and_hands_over_with_the_last_summary(self):
        for _ in range(guard.MAX_FAILED_ATTEMPTS - 1):
            self.assertEqual(self.post_edit(False)[0], 0)
        code, _, err = self.post_edit(False, "checkov CKV_AWS_53 main.tf:49")
        self.assertEqual(code, 2)
        self.assertIn("Hand over to a human", err)
        self.assertIn("CKV_AWS_53", err)
        # and further edits to that module are refused until a human resets it
        self.assertEqual(run_hook("pre-edit", {"tool_input": {"file_path": self.path}})[0], 2)
        self.assertEqual(run_hook("pre-edit", {"tool_input": {"file_path": "docs/SLO.md"}})[0], 0)
        guard.main(["guard.py", "reset", "storage/s3"])
        self.assertEqual(run_hook("pre-edit", {"tool_input": {"file_path": self.path}})[0], 0)

    def test_a_pass_resets_the_counter(self):
        self.post_edit(False)
        self.post_edit(False)
        self.assertEqual(self.post_edit(True)[0], 0)
        self.assertEqual(self.post_edit(False)[0], 0)
        self.assertEqual(self.post_edit(False)[0], 0)
        self.assertEqual(self.post_edit(False)[0], 2)

    def test_the_limit_is_three_by_default(self):
        self.assertEqual(guard.MAX_FAILED_ATTEMPTS, 3)


if __name__ == "__main__":
    unittest.main()
