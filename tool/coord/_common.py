"""Shared helpers for tool/coord/*.py.

Stdlib only, no third-party deps. Every script in this package shells out to `gh`
via subprocess argument lists (never a shell string), which is the whole point of
this package: PowerShell/`gh --jq` quoting was the single biggest time sink in the
first coordinator run. Passing argv lists sidesteps shell quoting entirely, on
Windows or anywhere else.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


class GhError(RuntimeError):
    """A `gh` invocation failed. str(e) is a short, printable message."""


def repo_root() -> Path:
    """Resolve the repo root from any cwd, so these scripts work from anywhere."""
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        raise GhError(f"not inside a git repo: {e}") from e
    return Path(out.stdout.strip())


def run_gh(args: list[str], input_text: str | None = None) -> str:
    """Run `gh <args...>`, return stdout (stripped). Raises GhError with a short
    stderr-derived message on non-zero exit."""
    try:
        proc = subprocess.run(
            ["gh", *args],
            capture_output=True,
            text=True,
            input=input_text,
        )
    except FileNotFoundError as e:
        raise GhError(f"gh CLI not found on PATH: {e}") from e
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "").strip().splitlines()
        short = msg[-1] if msg else f"gh exited {proc.returncode}"
        raise GhError(f"gh {' '.join(args[:2])} failed: {short}")
    return proc.stdout.strip()


def run_gh_json(args: list[str]):
    """Run `gh <args...> --json ...` and parse the result as JSON."""
    out = run_gh(args)
    try:
        return json.loads(out) if out else None
    except json.JSONDecodeError as e:
        raise GhError(f"gh returned non-JSON output: {e}") from e


def run_git(args: list[str], cwd: Path | None = None) -> str:
    try:
        proc = subprocess.run(
            ["git", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", *args],
            capture_output=True,
            text=True,
            cwd=str(cwd) if cwd else None,
        )
    except FileNotFoundError as e:
        raise GhError(f"git not found on PATH: {e}") from e
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "").strip().splitlines()
        short = msg[-1] if msg else f"git exited {proc.returncode}"
        raise GhError(f"git {' '.join(args[:2])} failed: {short}")
    return proc.stdout.strip()


def fail(message: str, code: int = 2) -> "int":
    print(f"error: {message}", file=sys.stderr)
    return code


def label_names(labels) -> list[str]:
    """`gh --json labels` returns a list of {name, ...} objects; flatten to names."""
    return [lbl["name"] for lbl in (labels or [])]
