#!/usr/bin/env python3
"""Create a coordinator-owned worktree: fetches, creates
`.worktrees/<owner>/<n>-<slug>` on branch `<owner>/<n>-<slug>` from
`origin/main`, and prints the absolute path.

Pass --fix to name the branch `<owner>/fix-<n>-<slug>` instead (the worktree
path is unchanged -- it stays keyed on the issue number, only the branch name
gets the fix- infix). This matches the opencode-muse convention in
.opencode/prompts/coordinator.md; other coordinators may ignore --fix.
"""

from __future__ import annotations

import argparse
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, repo_root, run_git  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("number", type=int)
    ap.add_argument("slug")
    ap.add_argument("--owner", required=True)
    ap.add_argument("--fix", action="store_true", help="branch is <owner>/fix-<n>-<slug>")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = repo_root()
    dir_name = f"{args.number}-{args.slug}"
    branch = f"{args.owner}/fix-{args.number}-{args.slug}" if args.fix else f"{args.owner}/{dir_name}"
    wt_path = root / ".worktrees" / args.owner / dir_name

    if wt_path.exists():
        return fail(f"{wt_path} already exists -- refusing to overwrite", 2)

    try:
        run_git(["fetch", "origin"], cwd=root)
        wt_path.parent.mkdir(parents=True, exist_ok=True)
        run_git(
            ["worktree", "add", "-b", branch, str(wt_path), "origin/main"],
            cwd=root,
        )
    except GhError as e:
        return fail(str(e))

    if args.json:
        import json
        print(json.dumps({"path": str(wt_path), "branch": branch}))
    else:
        print(str(wt_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
