"""Hard limits for the pipeline healer (PLAN 11.2 / 11.4). Pure functions, no network, no git: tested offline.

The healer pushes a commit to the branch of a failed run. Without limits it would push to main, keep pushing forever,
and let an LLM-written patch edit the files that decide what "passing" means. So it refuses to push when:

  * the branch is main (or master): a direct commit to main breaks the first standing guardrail,
  * the branch has no open pull request: nobody would review what it pushes,
  * it already pushed N commits to this branch (N = 3, the same limit as the local agent hooks),
  * the change touches a protected path: the checks themselves, the policy library or the pipeline.
"""
import os
from typing import Iterable

MAIN_BRANCHES = {"main", "master"}
HEALER_COMMIT_PREFIX = "chore(ci): auto-"
MAX_HEALER_COMMITS = int(os.getenv("HEALER_MAX_COMMITS", "3"))
AI_LABEL = "ai-generated"

PROTECTED_EXACT = {".checkov.yaml", ".trivyignore", ".tflint.hcl", "CODEOWNERS", ".github/CODEOWNERS"}
PROTECTED_PREFIXES = ("policy-library-repo/", ".github/", ".claude/", ".agents/hooks/")


def count_healer_commits(subjects: Iterable[str]) -> int:
    """How many of these commit subjects were made by the healer."""
    return sum(1 for s in subjects if s.startswith(HEALER_COMMIT_PREFIX))


def protected_changes(paths: Iterable[str]) -> list[str]:
    """The paths among these that only a human may change."""
    out = []
    for raw in paths:
        p = raw.strip().removeprefix("./")
        if p in PROTECTED_EXACT or p.startswith(PROTECTED_PREFIXES) or os.path.basename(p) == ".trivyignore":
            out.append(p)
    return out


def push_decision(head_branch: str, open_pr_number, prior_healer_commits: int, changed_paths: Iterable[str]) -> tuple[bool, str]:
    """(allowed, reason). The reason is printed in the run log so a person can see why the healer stood down."""
    branch = (head_branch or "").strip()
    if not branch:
        return False, "no branch name: nothing to push to"
    if branch in MAIN_BRANCHES:
        return False, f"refusing to push to {branch}: the healer never commits to the main branch"
    if not open_pr_number:
        return False, f"branch {branch} has no open pull request: nobody would review the fix"
    if prior_healer_commits >= MAX_HEALER_COMMITS:
        return False, f"already pushed {prior_healer_commits} healer commits to {branch} (limit {MAX_HEALER_COMMITS}): a human should look"
    blocked = protected_changes(changed_paths)
    if blocked:
        return False, "the patch touches protected paths that only a human edits: " + ", ".join(sorted(blocked))
    return True, "ok"
