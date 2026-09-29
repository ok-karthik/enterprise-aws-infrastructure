#!/usr/bin/env python3
"""Decide how much a CI plan run should cover (PLAN 8.5).

  full      plan every unit (push to main, scheduled/manual runs, or a PR that touches shared code)
  affected  plan only units Terragrunt sees as changed since the PR's base branch

Shared code = anything a unit reads from outside its own folder: the modules (IAC_MODULES_LOCAL points the leaves at
this checkout), _envcommon, root.hcl, the config registry, the policies and the pipeline itself. Terragrunt's
git filter only looks at files inside a unit, so a change to a module would otherwise plan nothing.

Usage: plan_scope.py <event_name> <base_ref>   (prints scope=..., filter=... for $GITHUB_OUTPUT)
"""
import subprocess
import sys

SHARED_PREFIXES = (
    "iac-modules-repo/",
    "policy-library-repo/",
    ".github/",
    "foundation-live-repo/_config/",
    "foundation-live-repo/_envcommon/",
    "workloads-live-repo/_envcommon/",
)
SHARED_FILES = ("foundation-live-repo/root.hcl", "workloads-live-repo/root.hcl", ".checkov.yaml", ".tflint.hcl")


def decide(event: str, changed: list[str]) -> str:
    if event != "pull_request":
        return "full"
    for path in changed:
        if path.startswith(SHARED_PREFIXES) or path in SHARED_FILES:
            return "full"
    return "affected"


def changed_files(base_ref: str) -> list[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", f"origin/{base_ref}...HEAD"], check=True, capture_output=True, text=True
    ).stdout
    return [line for line in out.splitlines() if line]


def main(argv: list[str]) -> int:
    event = argv[1] if len(argv) > 1 else ""
    base = argv[2] if len(argv) > 2 else "main"
    changed = changed_files(base) if event == "pull_request" else []
    scope = decide(event, changed)
    print(f"scope={scope}")
    print(f"filter={'--filter=[origin/' + base + '...HEAD]' if scope == 'affected' else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
