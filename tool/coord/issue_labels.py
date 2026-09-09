#!/usr/bin/env python3
"""Print an issue's labels, one per line (or as a JSON array with --json).

Exists purely so nobody writes another `gh issue view N --json labels --jq
'.labels[].name'` with escaped quotes in PowerShell.
"""

from __future__ import annotations

import argparse
import json
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, label_names, run_gh_json  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("number", type=int)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    try:
        issue = run_gh_json(["issue", "view", str(args.number), "--json", "labels"])
    except GhError as e:
        return fail(str(e))

    names = label_names(issue.get("labels"))
    if args.json:
        print(json.dumps(names))
    else:
        for name in names:
            print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
