"""Bridge from Claude Code to an `opencode-<model>` coordinator.

Start an iteration, then read the resulting session transcript. Every real
subprocess call is injectable so the logic is unit-testable without a live
opencode. The coordinator id is derived from the dispatched model, never
hard-coded.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "coord"))
from coordinator_id import coordinator_id  # noqa: E402

TIMEOUT_SECONDS = 3600


class BridgeError(RuntimeError):
    """An opencode invocation failed."""


def _runner(cmd):
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=TIMEOUT_SECONDS,
    )


def _first_json(text: str) -> dict:
    """Return the last complete JSON object in `text` (opencode run emits
    newline-delimited events; the final one carries the session id)."""
    for line in reversed([l for l in text.splitlines() if l.strip()]):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    raise BridgeError("no JSON object in opencode run output")


def run_iteration(prompt: str, agent: str = "coordinator", model: str | None = None,
                  runner=_runner) -> dict:
    """Run one coordinator iteration. Returns {session_id, raw}.

    When `model` is given, the coordinator id (`opencode-<model>`) is exported as
    LUNARLOG_COORDINATOR_ID so opencode.json injects it into the coordinator and
    coder prompts."""
    if model:
        os.environ["LUNARLOG_COORDINATOR_ID"] = coordinator_id(model)
    cmd = ["opencode", "run", "--agent", agent, "--format", "json"]
    if model:
        cmd += ["--model", model]
    cmd.append(prompt)
    proc = runner(cmd)
    if proc.returncode != 0:
        raise BridgeError(f"opencode run failed: {(proc.stderr or '').strip()}")
    data = _first_json(proc.stdout)
    session_id = data.get("sessionID") or data.get("session_id") or data.get("id")
    return {"session_id": session_id, "raw": data}


def export_session(session_id: str, runner=_runner) -> dict:
    proc = runner(["opencode", "export", session_id])
    if proc.returncode != 0:
        raise BridgeError(f"opencode export failed: {(proc.stderr or '').strip()}")
    return json.loads(proc.stdout)


def query_db(session_id: str, runner=_runner) -> list:
    """Best-effort fallback when `opencode export` is unusable: read the
    session's messages straight from opencode's SQLite store."""
    sql = f"select * from message where sessionID = '{session_id}' order by id"
    proc = runner(["opencode", "db", sql, "--format", "json"])
    if proc.returncode != 0:
        raise BridgeError(f"opencode db failed: {(proc.stderr or '').strip()}")
    return json.loads(proc.stdout) if proc.stdout.strip() else []


def read_session(session_id: str, runner=_runner) -> dict:
    """Prefer the exported transcript; fall back to the database."""
    try:
        return export_session(session_id, runner=runner)
    except (BridgeError, json.JSONDecodeError):
        return {"messages": query_db(session_id, runner=runner)}


def summarize_session(data, limit: int = 4000) -> str:
    """Collect the text a session produced, bounded to `limit` characters."""
    texts: list[str] = []

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "text" and isinstance(value, str):
                    texts.append(value)
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)
    joined = "\n".join(t for t in texts if t and t.strip())
    return joined[:limit]


def _main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--run", metavar="PROMPT")
    group.add_argument("--read", metavar="SESSION_ID")
    ap.add_argument("--agent", default="coordinator")
    ap.add_argument("--model", default=None)
    args = ap.parse_args()
    try:
        if args.run:
            result = run_iteration(args.run, agent=args.agent, model=args.model)
            print(json.dumps(result, indent=2))
        else:
            data = read_session(args.read)
            print(summarize_session(data))
    except (BridgeError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=__import__("sys").stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
