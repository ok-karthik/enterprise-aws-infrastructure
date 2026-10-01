#!/usr/bin/env python3
"""Guard rails for local coding agents (PLAN 11.2). One script, three modes, called by .claude/settings.json.

  guard.py pre-bash   Block commands that change real infrastructure or its state.
  guard.py pre-edit   Block edits to the files that decide what "passing" means, and to a module the agent gave up on.
  guard.py post-edit  After an edit inside a module, run `verify_module.py` for it and hand the short summary back.
  guard.py reset <category/name>   A human clears the attempt counter for a module.

The rules are tool-neutral and written in .agents/AGENTS.md ("Local agent guardrails"); this file is one implementation.
Any other agent tool can call the same script or read the same rules.

**These hooks run on a laptop and can be switched off. They save time; they are not the control.** The controls are
CODEOWNERS on these paths, branch protection, and the fact that no agent has credentials that can apply. See
docs/AGENT_AUTONOMY.md.

Protocol (Claude Code hooks): the hook JSON arrives on stdin. Exit code 2 blocks the tool call and shows stderr to the
agent. Any other exit code lets it through. post-edit returns JSON with `additionalContext` for the agent.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2]).resolve()
STATE_PATH = REPO_ROOT / ".agents" / "metrics" / "verify_attempts.json"
MAX_FAILED_ATTEMPTS = int(os.environ.get("AGENT_MAX_VERIFY_ATTEMPTS", "3"))  # N in PLAN 11.2

TOOLS = {"terraform", "terragrunt", "tofu"}
# Words that only wrap another command: look through them to the command they run.
WRAPPERS = {"sudo", "env", "time", "nohup", "nice", "exec", "command", "xargs", "watch", "timeout", "stdbuf", "caffeinate", "builtin"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "eval"}
STATE_WRITES = {"rm", "mv", "push"}  # terraform state <sub>
ALWAYS_BLOCKED = {"apply", "destroy", "force-unlock", "import", "taint", "untaint"}
READ_ONLY = {"plan", "validate", "fmt", "init", "show", "output", "graph", "providers", "version", "hcl", "render", "test", "console", "workspace", "list", "find", "info", "stack"}
PROTECTED_EXACT = {".checkov.yaml", ".trivyignore", ".claude/settings.json", ".claude/settings.local.json"}
PROTECTED_PREFIXES = ("policy-library-repo/", ".agents/hooks/")
WRITE_HINTS = re.compile(r"(\bsed\s+-i|\btee\b|\bmv\b|\brm\b|\bcp\b|\bgit\s+(checkout|restore|rm|mv)\b|\btruncate\b|\bdd\b|>>?|\bperl\s+-i|\bpython3?\b.*\bwrite|\bcat\b.*>)")


# ---------------------------------------------------------------------------
# pre-bash
# ---------------------------------------------------------------------------
def split_segments(command: str) -> list[str]:
    """Split on ; && || | & newlines and (), `, $( outside quotes so that `cd x && terraform apply` is two commands,
    while strings containing separators inside quotes or heredocs remain intact."""
    segments = []
    current: list[str] = []
    in_single = False
    in_double = False
    escaped = False
    heredoc_delim: Optional[str] = None
    lines = command.splitlines(keepends=True)

    for line in lines:
        if heredoc_delim is not None:
            if line.strip() == heredoc_delim:
                heredoc_delim = None
            continue

        m = re.search(r"<<-?\s*['\"]?([A-Za-z0-9_]+)['\"]?", line)
        if m:
            heredoc_delim = m.group(1)

        i = 0
        n = len(line)
        while i < n:
            c = line[i]
            if escaped:
                current.append(c)
                escaped = False
                i += 1
                continue
            if c == "\\" and not in_single:
                escaped = True
                current.append(c)
                i += 1
                continue
            if c == "'" and not in_double:
                in_single = not in_single
                current.append(c)
                i += 1
                continue
            if c == '"' and not in_single:
                in_double = not in_double
                current.append(c)
                i += 1
                continue

            if not in_single:
                if c == "`":
                    seg = "".join(current).strip()
                    if seg:
                        segments.append(seg)
                    current = []
                    i += 1
                    continue
                if line[i:i + 2] == "$(":
                    seg = "".join(current).strip()
                    if seg:
                        segments.append(seg)
                    current = []
                    i += 2
                    continue

            if not in_single and not in_double:
                if line[i:i + 2] in ("&&", "||"):
                    seg = "".join(current).strip()
                    if seg:
                        segments.append(seg)
                    current = []
                    i += 2
                    continue
                if c in (";", "|", "&", "\n", "(", ")"):
                    seg = "".join(current).strip()
                    if seg:
                        segments.append(seg)
                    current = []
                    i += 1
                    continue
            current.append(c)
            i += 1

    seg = "".join(current).strip()
    if seg:
        segments.append(seg)
    return segments


def tokens_of(segment: str) -> list[str]:
    try:
        return shlex.split(segment)
    except ValueError:
        # A quoted string was cut in two by the segment split (`sh -c "cd x && terragrunt destroy"`): drop the stray quotes.
        return segment.replace('"', "").replace("'", "").split()


def command_words(tokens: list[str]) -> list[str]:
    """Drop leading VAR=value assignments and wrapper words (and their flags or numbers), so the real command comes first."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        base = os.path.basename(t)
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif base in WRAPPERS:
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or re.match(r"^[0-9.]+[smhd]?$", tokens[i]) or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i])):
                i += 1
        else:
            break
    return tokens[i:]


def blocked_tool_call(words: list[str]) -> Optional[str]:
    """words[0] is terraform/terragrunt/tofu. Returns a reason, or None."""
    rest = words[1:]
    verbs = [w for w in rest if not w.startswith("-")]
    for i, w in enumerate(rest):
        if w in ALWAYS_BLOCKED:
            return f"`{words[0]} {w}` changes real infrastructure or its state"
        if w == "state" and any(x in STATE_WRITES for x in rest[i + 1:i + 3]):
            return f"`{words[0]} state {next(x for x in rest[i + 1:i + 3] if x in STATE_WRITES)}` edits Terraform state"
    all_mode = any(w in ("--all", "-a", "run-all") for w in rest) or (verbs[:1] == ["run-all"])
    if all_mode:
        # `run --all` is only allowed for read-only commands (`run --all plan`). Anything else, or nothing after it, is refused.
        after = [w for w in rest if not w.startswith("-") and w not in ("run", "run-all")]
        # (a flag's value, like `--log-format bare`, is also a word here, so look for a read-only command among them)
        if not any(w in READ_ONLY for w in after):
            return f"`{words[0]} run --all` without a read-only command (plan, validate, ...) can apply to every unit"
    return None


def check_segment_writes(segment: str) -> Optional[str]:
    """Detect whether a segment writes to a protected file via redirects or file-modifying tools."""
    for m in re.finditer(r"(?:>>?|1>|2>|&>)\s*([^\s;|&<>()]+)", segment):
        target = m.group(1).strip("'\"")
        if not target.startswith("&") and is_protected(target):
            return f"the command writes to {target}, which only a human edits"

    tokens = tokens_of(segment)
    words = command_words(tokens)
    if not words:
        return None

    head = os.path.basename(words[0])
    if head in ("rm", "mv", "cp", "truncate", "tee"):
        for arg in words[1:]:
            if not arg.startswith("-") and is_protected(arg):
                return f"the command writes to {arg}, which only a human edits"

    elif head in ("sed", "perl"):
        if any(w.startswith("-i") or w == "-i" for w in words[1:]):
            for arg in words[1:]:
                if not arg.startswith("-") and not (arg.startswith("s/") or arg.startswith("s|")) and is_protected(arg):
                    return f"the command writes to {arg}, which only a human edits"

    elif head == "git":
        subcmd = next((w for w in words[1:] if not w.startswith("-")), None)
        if subcmd in ("checkout", "restore", "rm", "mv"):
            for arg in words[2:]:
                if not arg.startswith("-") and arg != "--" and is_protected(arg):
                    return f"the command writes to {arg}, which only a human edits"

    elif head in ("python", "python3"):
        for token in re.split(r"[\s'\"=<>]+", segment):
            if is_protected(token) and any(w in segment for w in ("write", "open")):
                return f"the command writes to {token}, which only a human edits"
    return None


def check_command(command: str, depth: int = 0) -> Optional[str]:
    if depth > 3:
        return None
    for segment in split_segments(command):
        if (reason := check_segment_writes(segment)):
            return reason
        words = command_words(tokens_of(segment))
        if not words:
            continue
        head = os.path.basename(words[0])
        if head in TOOLS:
            if (reason := blocked_tool_call(words)):
                return reason
        elif head == "make":
            targets = [w for w in words[1:] if not w.startswith("-") and "=" not in w]
            if any(re.search(r"(apply|destroy|deploy|bootstrap)", t) for t in targets):
                t_str = " ".join(targets)
                return f"`make {t_str}` looks like an apply target"
        elif head in SHELLS:
            # bash -c 'terraform apply', eval "terragrunt destroy": look inside the string
            for arg in words[1:]:
                if not arg.startswith("-") and (reason := check_command(arg, depth + 1)):
                    return reason
        elif head in ("xargs", "ssh"):
            if (reason := check_command(" ".join(words[1:]), depth + 1)):
                return reason
        # A tool word hidden after other words (`echo x | sudo -E terraform apply`) is covered by the segment split.
    return None


def writes_protected_file(command: str) -> Optional[str]:
    for segment in split_segments(command):
        if (reason := check_segment_writes(segment)):
            return reason
    return None


# ---------------------------------------------------------------------------
# pre-edit and post-edit
# ---------------------------------------------------------------------------
def relative_path(file_path: str) -> str:
    p = Path(file_path)
    if not p.is_absolute():
        p = REPO_ROOT / p
    try:
        return p.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return p.as_posix()


def is_protected(path: str) -> bool:
    rel = relative_path(path) if path else ""
    rel = rel.removeprefix("./")
    return rel in PROTECTED_EXACT or rel.startswith(PROTECTED_PREFIXES) or os.path.basename(rel) == ".trivyignore"


def module_of(path: str) -> Optional[str]:
    parts = relative_path(path).split("/")
    if len(parts) >= 4 and parts[0] == "iac-modules-repo" and (REPO_ROOT / parts[0] / parts[1] / parts[2] / "main.tf").is_file():
        return f"{parts[1]}/{parts[2]}"
    return None


def load_state() -> dict:
    try:
        return json.loads(STATE_PATH.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n")


def record_result(state: dict, module: str, failed: bool, summary: str) -> dict:
    entry = state.get(module, {"failed": 0, "last_summary": ""})
    entry = {"failed": entry["failed"] + 1 if failed else 0, "last_summary": summary if failed else ""}
    return {**state, module: entry}


def limit_reached(state: dict, module: str) -> bool:
    return state.get(module, {}).get("failed", 0) >= MAX_FAILED_ATTEMPTS


def handover_message(module: str, state: dict) -> str:
    last = state.get(module, {}).get("last_summary", "")
    return (
        f"STOP: `make verify-module MODULE={module}` failed {MAX_FAILED_ATTEMPTS} times in a row. Do not keep editing this module. "
        f"Hand over to a human with the last result below. (A human clears the counter with "
        f"`python3 .agents/hooks/guard.py reset {module}`.)\n\n{last}"
    )


def run_verify(module: str) -> tuple[bool, str]:
    cmd = [sys.executable, str(REPO_ROOT / "workloads-live-repo" / "scripts" / "verify_module.py"), module]
    env = {**os.environ, "TF_PLUGIN_CACHE_DIR": os.environ.get("TF_PLUGIN_CACHE_DIR", str(Path.home() / ".terraform.d" / "plugin-cache"))}
    Path(env["TF_PLUGIN_CACHE_DIR"]).mkdir(parents=True, exist_ok=True)
    p = subprocess.run(cmd, cwd=REPO_ROOT, env=env, capture_output=True, text=True, timeout=900)
    return p.returncode == 0, (p.stdout + p.stderr).strip()


def hook_input() -> dict:
    try:
        return json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return {}


def block(message: str) -> int:
    print(message, file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else ""
    if mode == "reset":
        state = load_state()
        state.pop(argv[2] if len(argv) > 2 else "", None)
        save_state(state)
        return 0
    data = hook_input()
    tool_input = data.get("tool_input") or {}

    if mode == "pre-bash":
        if (reason := check_command(tool_input.get("command", ""))):
            return block(f"Blocked by the repo's agent guardrails (PLAN 11.2): {reason}. Agents never apply or edit state; a human runs that. Read-only commands (plan, validate, fmt) are fine.")
        return 0

    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if mode == "pre-edit":
        if is_protected(path):
            return block(f"Blocked by the repo's agent guardrails (PLAN 11.2): {relative_path(path)} decides what 'passing' means, so only a human edits it. Fix the code instead, or ask the owner.")
        module = module_of(path)
        if module and limit_reached(load_state(), module):
            return block(handover_message(module, load_state()))
        return 0

    if mode == "post-edit":
        module = module_of(path)
        if not module:
            return 0
        ok, summary = run_verify(module)
        state = record_result(load_state(), module, not ok, summary)
        save_state(state)
        if not ok and limit_reached(state, module):
            return block(handover_message(module, state))
        context = f"verify-module {module}: {'ok' if ok else 'FAILED'}\n{summary}"
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": context}}))
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
