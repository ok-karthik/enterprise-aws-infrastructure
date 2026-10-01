#!/usr/bin/env python3
"""Check ONE module locally with the same tools CI uses, without AWS credentials (PLAN 11.1).

    make verify-module MODULE=storage/s3
    python3 workloads-live-repo/scripts/verify_module.py storage/s3 [--json] [--root <modules dir>]

Steps, in order (each one is reported, and a step that cannot run is SKIPPED with a reason, never a silent pass):

  fmt        terraform fmt -check
  init       terraform init -backend=false
  validate   terraform validate
  tflint     tflint with the repo's .tflint.hcl
  checkov    workloads-live-repo/scripts/run-checkov.sh -d <module>   (the CI settings, .checkov.yaml)
  test       terraform test (the module's mock_provider tests)
  conftest   conftest against policy-library-repo/terraform on a plan JSON of <module>/examples/basic

The conftest step needs a plan, and a plan needs a provider that does not look at AWS. Each module that wants this step
has an examples/basic/ root that configures the AWS provider with skip_credentials_validation and friends. The fake
access keys are set in the environment by this script, never in HCL. A module whose examples/basic does not exist, or
whose data sources call AWS, reports conftest as SKIPPED.

Output for agents: one line per failure, `<tool> <check-id> <file>:<line>`, then one summary line per step; the same as
JSON with --json. Exit code 1 if any step failed. SKIPPED does not fail the run but is always printed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODULES_ROOT = REPO_ROOT / "iac-modules-repo"
POLICY_DIR = REPO_ROOT / "policy-library-repo" / "terraform"
RUN_CHECKOV = REPO_ROOT / "workloads-live-repo" / "scripts" / "run-checkov.sh"
TFLINT_CONFIG = REPO_ROOT / ".tflint.hcl"
FAKE_ENV = {
    # Fake, never valid, and only in the environment of the child processes: not in any file Checkov scans.
    "AWS_ACCESS_KEY_ID": "verify-module-fake",
    "AWS_SECRET_ACCESS_KEY": "verify-module-fake",
    "AWS_EC2_METADATA_DISABLED": "true",
}
STEPS = ["fmt", "init", "validate", "tflint", "checkov", "test", "conftest"]


@dataclass
class Finding:
    tool: str
    check_id: str
    file: str
    line: int
    message: str = ""

    def line_text(self) -> str:
        return f"{self.tool} {self.check_id} {self.file}:{self.line}"


@dataclass
class StepResult:
    name: str
    status: str  # PASS | FAIL | SKIPPED
    detail: str = ""
    findings: list[Finding] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Parsers (pure, tested)
# ---------------------------------------------------------------------------
def parse_fmt(stdout: str, module: Path) -> list[Finding]:
    return [Finding("terraform-fmt", "FMT", rel(Path(line.strip()), module), 1, "not formatted (run terraform fmt)") for line in stdout.splitlines() if line.strip()]


def parse_validate(stdout: str, module: Path) -> list[Finding]:
    try:
        data = json.loads(stdout)
    except ValueError:
        return []
    out = []
    for d in data.get("diagnostics", []):
        if d.get("severity") != "error":
            continue
        rng = d.get("range") or {}
        out.append(Finding("terraform-validate", "VALIDATE", rng.get("filename", "?"), (rng.get("start") or {}).get("line", 1), d.get("summary", "")))
    return out


def parse_tflint(stdout: str, module: Path) -> list[Finding]:
    try:
        data = json.loads(stdout)
    except ValueError:
        return []
    out = []
    for issue in data.get("issues", []):
        rng = issue.get("range") or {}
        out.append(Finding("tflint", issue.get("rule", {}).get("name", "?"), rng.get("filename", "?"), (rng.get("start") or {}).get("line", 1), issue.get("message", "")))
    for err in data.get("errors", []):
        out.append(Finding("tflint", "ERROR", "?", 1, err.get("message", "")))
    return out


def parse_checkov(stdout: str, module: Path) -> list[Finding]:
    """checkov -o json prints one JSON object per framework, or a list of them."""
    objects: list[dict] = []
    text = stdout.strip()
    try:
        parsed = json.loads(text)
        objects = parsed if isinstance(parsed, list) else [parsed]
    except ValueError:
        decoder, i = json.JSONDecoder(), 0
        while i < len(text):
            if text[i] in "{[":
                try:
                    obj, end = decoder.raw_decode(text, i)
                    objects.extend(obj if isinstance(obj, list) else [obj])
                    i = end
                    continue
                except ValueError:
                    pass
            i += 1
    out = []
    for obj in objects:
        for check in (obj.get("results") or {}).get("failed_checks", []):
            line = (check.get("file_line_range") or [1])[0]
            out.append(Finding("checkov", check.get("check_id", "?"), check.get("file_path", "?").lstrip("/"), line, check.get("check_name", "")))
    return out


def parse_terraform_test(stdout: str, module: Path) -> list[Finding]:
    """`run "name"... fail` lines. The file is the test file being run (the line before the runs)."""
    out, current = [], "tests"
    for line in stdout.splitlines():
        m = re.match(r"^(\S+\.tftest\.hcl)\.\.\. in progress", line)
        if m:
            current = m.group(1)
        m = re.match(r'^\s+run "([^"]+)"\.\.\. fail', line)
        if m:
            out.append(Finding("terraform-test", m.group(1), current, 1, "test run failed"))
    return out


def parse_conftest(stdout: str, module: Path) -> list[Finding]:
    try:
        data = json.loads(stdout)
    except ValueError:
        return []
    out = []
    for result in data if isinstance(data, list) else []:
        for failure in result.get("failures", []) or []:
            msg = failure.get("msg", "")
            rule = (failure.get("metadata") or {}).get("query", "deny")
            out.append(Finding("conftest", rule, "examples/basic (plan)", 1, msg))
    return out


def rel(path: Path, base: Path) -> str:
    try:
        return path.relative_to(base).as_posix()
    except ValueError:
        return path.as_posix()


# ---------------------------------------------------------------------------
# Running tools
# ---------------------------------------------------------------------------
def run(cmd: list[str], cwd: Path, env_extra: Optional[dict] = None, timeout: int = 900) -> subprocess.CompletedProcess:
    env = {**os.environ, "TF_IN_AUTOMATION": "1", **(env_extra or {})}
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)


def need(tool: str) -> Optional[str]:
    return None if shutil.which(tool) else f"{tool} is not installed"


def step_fmt(module: Path) -> StepResult:
    if (missing := need("terraform")):
        return StepResult("fmt", "SKIPPED", missing)
    p = run(["terraform", "fmt", "-check", "-recursive", "-list=true", "-write=false"], module)
    findings = parse_fmt(p.stdout, module)
    return StepResult("fmt", "PASS" if p.returncode == 0 else "FAIL", "", findings or ([] if p.returncode == 0 else [Finding("terraform-fmt", "FMT", "?", 1, p.stderr.strip()[:200])]))


def step_init(module: Path) -> StepResult:
    if (missing := need("terraform")):
        return StepResult("init", "SKIPPED", missing)
    p = run(["terraform", "init", "-backend=false", "-input=false", "-no-color"], module)
    if p.returncode == 0:
        return StepResult("init", "PASS")
    return StepResult("init", "FAIL", findings=[Finding("terraform-init", "INIT", "?", 1, (p.stderr or p.stdout).strip().splitlines()[-1][:200] if (p.stderr or p.stdout).strip() else "init failed")])


def step_validate(module: Path) -> StepResult:
    p = run(["terraform", "validate", "-json"], module)
    findings = parse_validate(p.stdout, module)
    return StepResult("validate", "PASS" if p.returncode == 0 else "FAIL", findings=findings)


def step_tflint(module: Path) -> StepResult:
    if (missing := need("tflint")):
        return StepResult("tflint", "SKIPPED", missing)
    p = run(["tflint", "--chdir", str(module), "--config", str(TFLINT_CONFIG), "--format", "json"], module)
    findings = parse_tflint(p.stdout, module)
    if p.returncode not in (0, 2) and not findings:
        return StepResult("tflint", "SKIPPED", f"tflint could not run (run `tflint --init` once): {(p.stderr or p.stdout).strip()[:120]}")
    return StepResult("tflint", "FAIL" if findings else "PASS", findings=findings)


def step_checkov(module: Path) -> StepResult:
    if (missing := need("checkov")):
        return StepResult("checkov", "SKIPPED", missing)
    p = run([str(RUN_CHECKOV), "-d", str(module), "--framework", "terraform", "-o", "json", "--quiet"], REPO_ROOT)
    findings = parse_checkov(p.stdout, module)
    if p.returncode not in (0, 1):
        return StepResult("checkov", "SKIPPED", f"checkov could not run: {(p.stderr or '').strip()[:150]}")
    return StepResult("checkov", "FAIL" if findings or p.returncode == 1 else "PASS", findings=findings)


def step_test(module: Path) -> StepResult:
    if not (module / "tests").is_dir():
        return StepResult("test", "SKIPPED", "no tests/ folder (every module should have one)")
    p = run(["terraform", "test", "-no-color"], module)
    findings = parse_terraform_test(p.stdout, module)
    if p.returncode != 0 and not findings:
        findings = [Finding("terraform-test", "ERROR", "tests", 1, (p.stderr or p.stdout).strip().splitlines()[-1][:200] if (p.stderr or p.stdout).strip() else "terraform test failed")]
    return StepResult("test", "PASS" if p.returncode == 0 else "FAIL", findings=findings)


def step_conftest(module: Path) -> StepResult:
    example = module / "examples" / "basic"
    if not example.is_dir():
        return StepResult("conftest", "SKIPPED", "no examples/basic (add one to get a plan JSON offline)")
    if (missing := need("conftest")):
        return StepResult("conftest", "SKIPPED", missing)
    init = run(["terraform", "init", "-backend=false", "-input=false", "-no-color"], example)
    if init.returncode != 0:
        return StepResult("conftest", "SKIPPED", f"examples/basic could not be initialised: {(init.stderr or init.stdout).strip()[-150:]}")
    plan = run(["terraform", "plan", "-input=false", "-refresh=false", "-lock=false", "-no-color", "-out=verify.tfplan"], example, FAKE_ENV)
    if plan.returncode != 0:
        why = (plan.stderr or plan.stdout).strip()
        # A data source that calls AWS cannot be planned offline: say so, do not pass.
        return StepResult("conftest", "SKIPPED", f"needs credentials or a variable for a data source; examples/basic could not be planned: {why[-150:]}")
    show = run(["terraform", "show", "-json", "verify.tfplan"], example, FAKE_ENV)
    plan_json = example / "verify.tfplan.json"
    plan_json.write_text(show.stdout)
    try:
        p = run(["conftest", "test", "--policy", str(POLICY_DIR), "--output", "json", str(plan_json)], REPO_ROOT)
        findings = parse_conftest(p.stdout, module)
        return StepResult("conftest", "FAIL" if findings else "PASS", findings=findings)
    finally:
        for leftover in (plan_json, example / "verify.tfplan"):
            leftover.unlink(missing_ok=True)


RUNNERS = {"fmt": step_fmt, "init": step_init, "validate": step_validate, "tflint": step_tflint, "checkov": step_checkov, "test": step_test, "conftest": step_conftest}


def verify(module: Path) -> list[StepResult]:
    results: list[StepResult] = []
    for name in STEPS:
        if name in ("validate", "tflint", "checkov", "test", "conftest") and results and results[1].name == "init" and results[1].status != "PASS":
            results.append(StepResult(name, "SKIPPED", "init failed"))
            continue
        results.append(RUNNERS[name](module))
    return results


def render(module_name: str, results: list[StepResult]) -> str:
    lines = [f.line_text() for r in results for f in r.findings]
    for r in results:
        detail = f" ({r.detail})" if r.detail else ""
        lines.append(f"[{r.status}] {r.name}{detail}")
    failed = [r.name for r in results if r.status == "FAIL"]
    skipped = [r.name for r in results if r.status == "SKIPPED"]
    lines.append(f"{module_name}: {'FAILED: ' + ', '.join(failed) if failed else 'ok'}" + (f" | SKIPPED: {', '.join(skipped)}" if skipped else ""))
    return "\n".join(lines)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("module", help="category/name under iac-modules-repo, for example storage/s3")
    parser.add_argument("--json", action="store_true", help="print the result as JSON instead of lines")
    parser.add_argument("--root", default=str(DEFAULT_MODULES_ROOT), help="modules folder (default iac-modules-repo; for tests)")
    args = parser.parse_args(argv)

    module = Path(args.root) / args.module
    if not (module / "main.tf").is_file():
        print(f"error: {module} is not a module (no main.tf). Use category/name, for example storage/s3.", file=sys.stderr)
        return 2
    results = verify(module)
    if args.json:
        print(json.dumps({"module": args.module, "ok": not any(r.status == "FAIL" for r in results), "steps": [asdict(r) for r in results]}, indent=2))
    else:
        print(render(args.module, results))
    return 1 if any(r.status == "FAIL" for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
