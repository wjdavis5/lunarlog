#!/usr/bin/env python3
"""Derive a coordinator id from the model that coordinator is running.

The id is `opencode-<model>`, where `<model>` is the leading segment of the model
name (after the provider slash, up to the first `-` or `.`):

    opencode/muse-spark-1.3-contributor-free -> opencode-muse
    deepseek/deepseek-v4-flash               -> opencode-deepseek
    opencode/mimo-v2.5-free                  -> opencode-mimo

This is what lets several OpenCode coordinators run at once, one per model, each
with its own `owner:<id>` label, `<id>/` branch prefix, `.worktrees/<id>/` root,
and `docs/coordinator/<id>/` state directory. The id is never hard-coded.

The launcher (`run_opencode.ps1`, `tool/orchestrator/opencode_bridge.py`) computes
this and exports `LUNARLOG_COORDINATOR_ID`, which `opencode.json` injects into the
coordinator and coder prompts as `COORDINATOR_ID=<id>`.
"""

from __future__ import annotations

import argparse
import re
import sys

FAMILY_SEP_RE = re.compile(r"[-.]")
ID_PREFIX = "opencode-"


class CoordinatorIdError(ValueError):
    """The model id could not be turned into a coordinator id."""


def coordinator_id(model: str) -> str:
    """`provider/model-name` -> `opencode-<model-name's leading segment>`."""
    provider, sep, name = (model or "").partition("/")
    if not sep or not provider.strip() or not name.strip():
        raise CoordinatorIdError(f"not a provider/model id: {model!r}")
    family = FAMILY_SEP_RE.split(name.strip(), 1)[0]
    if not family:
        raise CoordinatorIdError(f"empty model family in {model!r}")
    return f"{ID_PREFIX}{family}"


def _main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", required=True, help="a provider/model id, e.g. deepseek/deepseek-v4-flash")
    ap.add_argument("--export", action="store_true",
                    help="print `LUNARLOG_COORDINATOR_ID=<id>` for a shell to eval")
    args = ap.parse_args()
    try:
        cid = coordinator_id(args.model)
    except CoordinatorIdError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    print(f"LUNARLOG_COORDINATOR_ID={cid}" if args.export else cid)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
