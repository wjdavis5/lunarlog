#!/usr/bin/env python3
"""List open PRs: number, head branch, labels, CI rollup, review decision.

--owner <id> together with --mine filters to PRs that are that coordinator's by
BOTH ownership markers: head branch starts with "<id>/" AND the PR carries an
"owner:<id>" label. --owner alone (no --mine) is accepted for symmetry but does
not filter -- pass --mine explicitly to filter, so a bare --owner never silently
hides PRs someone forgot to double-check.
"""

from __future__ import annotations

import argparse
import json
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, label_names, run_gh_json  # noqa: E402


def ci_rollup(pr) -> str:
    rollup = pr.get("statusCheckRollup") or []
    if not rollup:
        return "none"
    states = {c.get("conclusion") or c.get("state") or "PENDING" for c in rollup}
    if "FAILURE" in states or "ERROR" in states:
        return "FAILURE"
    if states - {"SUCCESS"}:
        return "PENDING"
    return "SUCCESS"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--owner", default=None)
    ap.add_argument("--mine", action="store_true", help="filter to --owner's PRs by both markers")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if args.mine and not args.owner:
        return fail("--mine requires --owner", 2)

    try:
        prs = run_gh_json([
            "pr", "list", "--state", "open", "--limit", "200",
            "--json", "number,headRefName,labels,statusCheckRollup,reviewDecision",
        ]) or []
    except GhError as e:
        return fail(str(e))

    rows = []
    for pr in prs:
        labels = label_names(pr.get("labels"))
        rows.append({
            "number": pr["number"],
            "head": pr["headRefName"],
            "labels": labels,
            "ci": ci_rollup(pr),
            "reviewDecision": pr.get("reviewDecision") or "",
        })

    if args.mine:
        prefix = f"{args.owner}/"
        owner_label = f"owner:{args.owner}"
        rows = [r for r in rows if r["head"].startswith(prefix) and owner_label in r["labels"]]

    if args.json:
        print(json.dumps(rows, indent=2))
        return 0

    for r in rows:
        print(f"#{r['number']}\t{r['head']}\t{','.join(r['labels'])}\t{r['ci']}\t{r['reviewDecision']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
