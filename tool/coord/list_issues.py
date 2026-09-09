#!/usr/bin/env python3
"""List open GitHub issues, plain-text by default: `#n<TAB>labels<TAB>title`.

With --eligible <COORDINATOR_ID>, applies the standard pick filter (drops
in-progress, needs-human-review, blocked, epic[:*], wontfix, and anything
carrying any owner:* label, plus anything with an open `depends on: #N` /
`blocked by #N` in its body) and sorts P0 -> P1 -> P2 -> P3 -> unlabeled,
then by issue number.

Repo priority labels are P0-P3, not priority:P0.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, label_names, run_gh_json  # noqa: E402

EXCLUDE_EXACT = {"in-progress", "needs-human-review", "blocked", "wontfix"}
PRIORITY_ORDER = ["P0", "P1", "P2", "P3"]
DEP_RE = re.compile(r"(?:depends on|blocked by)\s*:?\s*#(\d+)", re.IGNORECASE)


def is_excluded(labels: list[str]) -> bool:
    for name in labels:
        if name in EXCLUDE_EXACT:
            return True
        if name == "epic" or name.startswith("epic:"):
            return True
        if name.startswith("owner:"):
            return True
    return False


def priority_key(labels: list[str], number: int) -> tuple:
    for i, p in enumerate(PRIORITY_ORDER):
        if p in labels:
            return (i, number)
    return (len(PRIORITY_ORDER), number)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--eligible", metavar="COORDINATOR_ID", default=None,
                     help="apply the pick filter and priority sort for this coordinator")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    try:
        issues = run_gh_json([
            "issue", "list", "--state", "open", "--limit", "500",
            "--json", "number,title,labels,body",
        ]) or []
    except GhError as e:
        return fail(str(e))

    rows = []
    for issue in issues:
        labels = label_names(issue.get("labels"))
        rows.append({
            "number": issue["number"],
            "title": issue["title"],
            "labels": labels,
            "body": issue.get("body") or "",
        })

    if args.eligible:
        open_numbers = {r["number"] for r in rows}
        filtered = []
        for r in rows:
            if is_excluded(r["labels"]):
                continue
            deps = [int(m) for m in DEP_RE.findall(r["body"])]
            if any(d in open_numbers for d in deps):
                continue
            filtered.append(r)
        filtered.sort(key=lambda r: priority_key(r["labels"], r["number"]))
        rows = filtered

    if args.json:
        print(json.dumps(rows, indent=2))
        return 0

    for r in rows:
        print(f"#{r['number']}\t{','.join(r['labels'])}\t{r['title']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
