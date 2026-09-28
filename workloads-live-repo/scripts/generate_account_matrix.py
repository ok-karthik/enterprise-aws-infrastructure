#!/usr/bin/env python3
"""Generate the CI account matrix from the account registry (PLAN 2.6).

Reads foundation-live-repo/_config/accounts.hcl and emits one matrix entry per account that
  - has ci = true in the registry,
  - has a live folder (workloads-live-repo/<name> or foundation-live-repo/<name>), and
  - has a real account id (not a 000000000xxx placeholder).
Everything else is skipped with a notice that says why, so a placeholder never turns CI red.

Each job builds its role ARN from the account id, so there are no per-environment role variables:
  arn:aws:iam::<id>:role/github-actions-plan   (plan, governance, drift: read-only)
  arn:aws:iam::<id>:role/github-actions-apply  (apply and destroy: only from the account's GitHub Environment)

Usage:
  generate_account_matrix.py                       print the matrix JSON
  generate_account_matrix.py --github-output       also write matrix= and count= to $GITHUB_OUTPUT
  generate_account_matrix.py --account NAME        print one entry (must be in the matrix); with
                                                   --github-output write its fields to $GITHUB_OUTPUT
No AWS access is needed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
REGISTRY = "foundation-live-repo/_config/accounts.hcl"
LIVE_REPOS = ("workloads-live-repo", "foundation-live-repo")

# Apply order: the management and core accounts first, then dev, staging, prod last.
APPLY_ORDER = ["management", "core", "dev", "staging", "prod"]


def parse_registry(text: str) -> dict[str, dict[str, str]]:
    """Parse the accounts map of accounts.hcl into {name: {field: value}}."""
    accounts: dict[str, dict[str, str]] = {}
    for match in re.finditer(r"^    ([A-Za-z0-9_-]+) = \{\n(.*?)^    \}", text, re.M | re.S):
        name, body = match.groups()
        fields: dict[str, str] = {}
        for line in body.splitlines():
            m = re.match(r'^\s+(\w+)\s*=\s*(?:"([^"]*)"|([^\s#]+))', line)
            if m:
                fields[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
        accounts[name] = fields
    return accounts


def github_environment(name: str, fields: dict[str, str]) -> str:
    """The GitHub Environment whose jobs may assume github-actions-apply in this account."""
    if name == "management":
        return "management"
    env = fields.get("env", "")
    if env == "global":
        return "core"  # Security and Infrastructure accounts
    return env  # dev | staging | prod


OU_FOLDER = {
    "Security": "security",
    "Infrastructure": "infrastructure",
    "NonProd": "workloads/nonprod",
    "Prod": "workloads/prod",
    "Root": "",
}


def find_account_dir(root: Path, name: str, ou: str) -> Path | None:
    """Find the live folder for an account, checking both OU-grouped and flat paths."""
    ou_sub = OU_FOLDER.get(ou, "")
    for repo in LIVE_REPOS:
        if ou_sub:
            candidate = root / repo / ou_sub / name
            if candidate.is_dir():
                return candidate
        candidate = root / repo / name
        if candidate.is_dir():
            return candidate
    return None


def build_matrix(registry_text: str, root: Path = REPO_ROOT) -> tuple[list[dict], list[str]]:
    """Return (matrix entries in apply order, notices for the accounts that were skipped)."""
    entries: list[dict] = []
    notices: list[str] = []
    for name, fields in parse_registry(registry_text).items():
        if fields.get("ci") != "true":
            continue
        account_id = fields.get("id", "")
        if not re.fullmatch(r"\d{12}", account_id):
            notices.append(f"{name}: skipped, '{account_id}' is not a 12-digit account id")
            continue
        if account_id.startswith("00000000"):
            notices.append(f"{name}: skipped, {account_id} is still a placeholder id (fill in the real account id in {REGISTRY})")
            continue
        account_dir = find_account_dir(root, name, fields.get("ou", ""))
        if account_dir is None:
            notices.append(f"{name}: skipped, no live folder found ({' or '.join(f'{r}/{name}' for r in LIVE_REPOS)})")
            continue
        rel_working_dir = account_dir.relative_to(root).as_posix()
        environment = github_environment(name, fields)
        entries.append(
            {
                "account": name,
                "account_id": account_id,
                "env": fields.get("env", ""),
                "github_environment": environment,
                "working_directory": rel_working_dir,
                "plan_role_arn": f"arn:aws:iam::{account_id}:role/github-actions-plan",
                "apply_role_arn": f"arn:aws:iam::{account_id}:role/github-actions-apply",
            }
        )
    entries.sort(key=lambda e: (APPLY_ORDER.index(e["github_environment"]) if e["github_environment"] in APPLY_ORDER else len(APPLY_ORDER), e["account"]))
    return entries, notices


def write_github_output(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        sys.exit("--github-output needs $GITHUB_OUTPUT (it is set inside GitHub Actions)")
    with open(path, "a", encoding="utf-8") as fh:
        for key, value in values.items():
            fh.write(f"{key}={value}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--github-output", action="store_true", help="write results to $GITHUB_OUTPUT")
    parser.add_argument("--account", help="print only this account's entry (it must be in the matrix)")
    args = parser.parse_args(argv)

    entries, notices = build_matrix((REPO_ROOT / REGISTRY).read_text(encoding="utf-8"))
    for notice in notices:
        print(f"::notice title=Account skipped::{notice}", file=sys.stderr)

    if args.account:
        entry = next((e for e in entries if e["account"] == args.account), None)
        if entry is None:
            sys.exit(f"Account '{args.account}' is not in the CI matrix (ci = true, a live folder and a real id are required).")
        print(json.dumps(entry))
        if args.github_output:
            write_github_output({k: str(v) for k, v in entry.items()})
        return 0

    matrix = {"include": entries}
    print(json.dumps(matrix))
    if args.github_output:
        write_github_output({"matrix": json.dumps(matrix), "count": str(len(entries))})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
