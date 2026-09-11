#!/usr/bin/env python3
"""List open GitHub issues, plain-text by default: `#n<TAB>labels<TAB>title`.

With --eligible <COORDINATOR_ID>, applies the standard pick filter (drops
in-progress, needs-human-review, blocked, wontfix, epic CONTAINERS, any FOREIGN
owner:* label, anything whose body has an open `depends on: #N` / `blocked by
#N`, and anything an open PR already closes) and sorts P0 -> P1 -> P2 -> P3 ->
unlabeled, then by issue number. The coordinator's OWN owner:<id> label without
in-progress is reclaimable, not excluded.

An epic CONTAINER (a bare `epic` label, or a title starting with "Epic:") is
excluded as non-dispatchable. An `epic:<theme>` label alone is NOT a container
marker -- it is used repo-wide as a theme tag on ordinary, individually-sized
issues (e.g. `epic:tracking-model` on a normal `feat(logging): ...` issue), and
such issues stay eligible (#448: the original blanket `epic:*` exclusion here
emptied the eligible queue for every coordinator, since virtually every open
issue carries a theme label).

With --stuck, lists stuck claims: open issues carrying `in-progress` with no
`owner:*` label (the mutual-backoff edge in claim.py). If both --stuck and
--eligible are passed, --stuck wins and --eligible is ignored. Run
`list_issues.py --stuck` to reconcile a stuck claim.

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
DEP_PHRASE_RE = re.compile(r"\b(?:depends on|blocked by)\b", re.IGNORECASE)
NEGATED_RE = re.compile(r"\b(?:not\s+blocked\s+by|unblocked)\b", re.IGNORECASE)
ISSUE_REF_RE = re.compile(r"(?:#|/issues/)(\d+)")
CLOSES_RE = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", re.IGNORECASE)


def is_epic_container(labels: list[str], title: str) -> bool:
    """True for an epic CONTAINER issue -- a bare `epic` label, or a title
    starting with "Epic:" (the repo's own convention; every current container
    uses both). An `epic:<theme>` label alone does not make an issue a
    container -- it is a theme tag applied to ordinary sized issues too."""
    if "epic" in labels:
        return True
    return title.startswith("Epic:") or title.startswith("Epic ")


def is_excluded(labels: list[str], self_owner: str | None = None, title: str = "") -> bool:
    if is_epic_container(labels, title):
        return True
    own = f"owner:{self_owner}" if self_owner else None
    for name in labels:
        if name in EXCLUDE_EXACT:
            return True
        if name.startswith("owner:") and name != own:
            return True
    return False


def is_stuck(labels: list[str]) -> bool:
    """True for a stuck claim: `in-progress` with no `owner:*` label."""
    return "in-progress" in labels and not any(
        name.startswith("owner:") for name in labels
    )


def dependency_numbers(body: str) -> set[int]:
    """Every issue referenced in a live dependency sentence. A negated sentence
    ("not blocked by #5", "unblocked by #5") is not a dependency."""
    deps: set[int] = set()
    for line in (body or "").splitlines():
        if NEGATED_RE.search(line):
            continue
        if DEP_PHRASE_RE.search(line):
            deps.update(int(m) for m in ISSUE_REF_RE.findall(line))
    return deps


def open_pr_issue_numbers() -> set[int]:
    """Issue numbers an open PR already closes/fixes/resolves."""
    try:
        prs = run_gh_json([
            "pr", "list", "--state", "open", "--limit", "200", "--json", "number,body",
        ]) or []
    except GhError:
        return set()
    nums: set[int] = set()
    for pr in prs:
        nums.update(int(m) for m in CLOSES_RE.findall(pr.get("body") or ""))
    return nums


def priority_key(labels: list[str], number: int) -> tuple:
    for i, p in enumerate(PRIORITY_ORDER):
        if p in labels:
            return (i, number)
    return (len(PRIORITY_ORDER), number)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--eligible", metavar="COORDINATOR_ID", default=None,
                     help="apply the pick filter and priority sort for this coordinator")
    ap.add_argument("--stuck", action="store_true",
                     help="list stuck claims (in-progress with no owner:* label); "
                     "wins over --eligible, which is ignored when both are passed")
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

    if args.stuck:
        rows = [r for r in rows if is_stuck(r["labels"])]
    elif args.eligible:
        open_numbers = {r["number"] for r in rows}
        claimed_by_pr = open_pr_issue_numbers()
        filtered = []
        for r in rows:
            if is_excluded(r["labels"], args.eligible, r["title"]):
                continue
            if r["number"] in claimed_by_pr:
                continue
            deps = dependency_numbers(r["body"])
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
