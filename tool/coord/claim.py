#!/usr/bin/env python3
"""Claim a GitHub issue for one coordinator, atomically (as atomically as GitHub
labels allow — see the race-loss note below).

Exit codes: 0 = claimed, 1 = lost the race / already claimed, 2 = error.

Sequence (matches docs/coordinator/README.md "Claiming an issue" exactly):
  1. `gh issue view <n> --json labels` -- abort (exit 1) if `in-progress` present.
  2. `gh issue edit <n> --add-label in-progress --add-label owner:<id>`.
  3. Comment: "Claimed by <id>. Branch: <branch>".
  4. Re-read labels. If a foreign owner:* label is present, another coordinator
     won the race: remove only our own owner:<id> label, leave in-progress alone,
     exit 1.

Known limitation: if two coordinators run step 1 within the same instant (before
either has added a label), both can pass the check and both add their owner:
label. The re-check in step 4 then sees a foreign owner: label from both sides,
and both back off -- leaving the issue `in-progress` with no owner label. This is
an accepted, documented edge case (see the PR that introduced this script): the
issue simply will not be re-picked (in-progress excludes it from --eligible),
and shows up via `list_issues.py --stuck` as a stuck claim to reconcile.
It is not silently lost.
"""

from __future__ import annotations

import argparse
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, label_names, run_gh, run_gh_json  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("number", type=int, help="issue number")
    ap.add_argument("--owner", required=True, help="this coordinator's id")
    ap.add_argument("--branch", required=True, help="branch name to record in the claim comment")
    args = ap.parse_args()

    n = str(args.number)
    owner_label = f"owner:{args.owner}"

    added = False
    try:
        issue = run_gh_json(["issue", "view", n, "--json", "labels"])
        labels = label_names(issue.get("labels"))
        if "in-progress" in labels:
            print(f"issue #{n} already has in-progress -- not claiming", file=sys.stderr)
            return 1

        # Never mutate an issue another coordinator already owns, even if it
        # carries no in-progress label. Abort before adding anything.
        foreign = [
            lbl for lbl in labels
            if lbl.startswith("owner:") and lbl != owner_label
        ]
        if foreign:
            print(
                f"issue #{n}: already owned by {', '.join(foreign)} -- not claiming",
                file=sys.stderr,
            )
            return 1

        run_gh(["issue", "edit", n, "--add-label", "in-progress", "--add-label", owner_label])
        added = True
        run_gh(["issue", "comment", n, "--body", f"Claimed by {args.owner}. Branch: {args.branch}"])

        recheck = run_gh_json(["issue", "view", n, "--json", "labels"])
        recheck_labels = label_names(recheck.get("labels"))
        foreign_owners = [
            lbl for lbl in recheck_labels
            if lbl.startswith("owner:") and lbl != owner_label
        ]
        if foreign_owners:
            run_gh(["issue", "edit", n, "--remove-label", owner_label])
            added = False
            print(
                f"issue #{n}: lost the race to {', '.join(foreign_owners)} -- "
                f"removed {owner_label}, left in-progress in place",
                file=sys.stderr,
            )
            return 1
    except GhError as e:
        # Roll back our own label so a partial claim never leaves the issue
        # stuck with an owner and no STATE row to reconcile.
        if added:
            try:
                run_gh(["issue", "edit", n, "--remove-label", owner_label])
            except GhError:
                pass
        return fail(str(e))

    print(f"claimed #{n} for {args.owner} on {args.branch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
