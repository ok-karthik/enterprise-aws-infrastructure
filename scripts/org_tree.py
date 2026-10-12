#!/usr/bin/env python3
"""Print the AWS Organizations OU tree with the account in each OU and the live folder of each account.

The OU tree comes from iac-live-repo/_config/organization.hcl (organizational_units), the accounts from the
registry (accounts.hcl, plus accounts.local.hcl for the real ids). No AWS access is needed.

Usage:
  org_tree.py            print the tree (real account ids if accounts.local.hcl provides them)
  org_tree.py --readme   rewrite the block between <!-- org-tree:start --> and <!-- org-tree:end --> in iac-live-repo/README.md
  org_tree.py --check    exit 1 if that block is stale (CI)

The README block never contains an account id (the repository is public): it shows only "real" or "placeholder",
taken from the committed registry alone, so CI and a laptop produce the same block.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_account_matrix import (  # noqa: E402
    LIVE_REPO,
    REGISTRY,
    REPO_ROOT,
    load_accounts,
    load_ous,
    ou_folder,
    parse_ous,
    parse_registry,
)

README = "iac-live-repo/README.md"
START = "<!-- org-tree:start -->"
END = "<!-- org-tree:end -->"


def is_placeholder(account_id: str) -> bool:
    return not re.fullmatch(r"\d{12}", account_id) or account_id.startswith("00000000")


def id_label(account_id: str, show_ids: bool) -> str:
    if is_placeholder(account_id):
        return "placeholder"
    return account_id if show_ids else "real"


def render_tree(accounts: dict[str, dict[str, str]], ous: dict[str, str | None], root: Path, show_ids: bool) -> str:
    """The tree as text: Root, its accounts, then every OU in map order with its accounts and child OUs."""

    def accounts_in(ou: str) -> list[str]:
        return sorted(n for n, f in accounts.items() if f.get("ou") == ou)

    def line(prefix: str, branch: str, name: str, account: str | None, ou: str) -> str:
        if account is None:
            return f"{prefix}{branch}{name}"
        folder = f"{LIVE_REPO}/{ou_folder(ou, ous)}/{account}"
        missing = "" if (root / folder).is_dir() else "  (no live folder)"
        label = f"{prefix}{branch}{name}"
        return f"{label:<36}{id_label(accounts[account].get('id', ''), show_ids):<13}{folder}{missing}"

    def children_of(ou: str) -> list[tuple[str, str | None]]:
        """Entries under an OU: its accounts first, then its child OUs in map order."""
        entries: list[tuple[str, str | None]] = [("account", a) for a in accounts_in(ou)]
        entries += [("ou", child) for child, parent in ous.items() if parent == ou]
        return entries

    out: list[str] = []

    def walk(ou: str, prefix: str) -> None:
        entries = children_of(ou)
        for i, (kind, name) in enumerate(entries):
            last = i == len(entries) - 1
            branch = "└── " if last else "├── "
            nxt = prefix + ("    " if last else "│   ")
            if kind == "account":
                out.append(line(prefix, branch, name, name, ou))
            else:
                out.append(f"{prefix}{branch}{name}" + ("" if children_of(name) else "  (no accounts)"))
                walk(name, nxt)

    out.append("Root")
    root_children = [("account", a) for a in accounts_in("Root")] + [("ou", o) for o, parent in ous.items() if parent is None]
    for i, (kind, name) in enumerate(root_children):
        last = i == len(root_children) - 1
        branch = "└── " if last else "├── "
        nxt = "    " if last else "│   "
        if kind == "account":
            out.append(line("", branch, name, name, "Root"))
        else:
            out.append(f"{branch}{name}" + ("" if children_of(name) else "  (no accounts)"))
            walk(name, nxt)
    return "\n".join(out) + "\n"


def readme_block(root: Path) -> str:
    registry = parse_registry((root / REGISTRY).read_text(encoding="utf-8"))
    tree = render_tree(registry, load_ous(root), root, show_ids=False)
    return f"{START}\n```text\n{tree}```\n{END}"


def replace_block(readme: str, block: str) -> str | None:
    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
    return pattern.sub(lambda _: block, readme, count=1) if pattern.search(readme) else None


def main(argv: list[str] | None = None, root: Path = REPO_ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--readme", action="store_true", help="rewrite the org-tree block in iac-live-repo/README.md")
    parser.add_argument("--check", action="store_true", help="exit 1 if the org-tree block in iac-live-repo/README.md is stale")
    args = parser.parse_args(argv)

    if args.readme or args.check:
        path = root / README
        current = path.read_text(encoding="utf-8")
        updated = replace_block(current, readme_block(root))
        if updated is None:
            print(f"❌ {README} has no {START} ... {END} block", file=sys.stderr)
            return 1
        if args.check:
            if updated != current:
                print(f"org tree in {README} is stale: run make org-tree", file=sys.stderr)
                return 1
            print(f"✅ org tree in {README} is up to date.")
            return 0
        path.write_text(updated, encoding="utf-8")
        print(f"{README}: org-tree block {'updated' if updated != current else 'already up to date'}")
        return 0

    registry = load_accounts((root / REGISTRY).read_text(encoding="utf-8"), root)
    print(render_tree(registry, load_ous(root), root, show_ids=True), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
