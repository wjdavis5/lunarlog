#!/usr/bin/env python3
"""Remove a git worktree, refusing if it is not under `.worktrees/<owner>/`.

This is the one guard standing between a coordinator and accidentally deleting
another coordinator's (or a human's) in-progress work -- never bypass it.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, repo_root, run_git  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path")
    ap.add_argument("--owner", required=True)
    ap.add_argument("--force", action="store_true", help="pass -f to `git worktree remove`")
    args = ap.parse_args()

    root = repo_root()
    target = Path(args.path).resolve()
    allowed_prefix = (root / ".worktrees" / args.owner).resolve()

    try:
        target.relative_to(allowed_prefix)
    except ValueError:
        return fail(
            f"{target} is not under {allowed_prefix} -- refusing to remove a "
            f"worktree outside owner '{args.owner}'s prefix",
            1,
        )

    try:
        cmd = ["worktree", "remove"]
        if args.force:
            cmd.append("--force")
        cmd.append(str(target))
        run_git(cmd, cwd=root)
    except GhError as e:
        return fail(str(e))

    print(f"removed {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
