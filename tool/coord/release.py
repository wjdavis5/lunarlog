#!/usr/bin/env python3
"""Release a claimed issue: removes `in-progress` and `owner:<id>`, only if
`owner:<id>` is present on the issue. Refuses (exit 1) otherwise -- a coordinator
must never remove another coordinator's claim.
"""

from __future__ import annotations

import argparse
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from _common import GhError, fail, label_names, run_gh, run_gh_json  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("number", type=int)
    ap.add_argument("--owner", required=True)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    n = str(args.number)
    owner_label = f"owner:{args.owner}"

    try:
        issue = run_gh_json(["issue", "view", n, "--json", "labels"])
        labels = label_names(issue.get("labels"))
        if owner_label not in labels:
            print(
                f"issue #{n} does not carry {owner_label} -- refusing to release "
                f"(current labels: {', '.join(labels) or 'none'})",
                file=sys.stderr,
            )
            return 1
        run_gh(["issue", "edit", n, "--remove-label", "in-progress", "--remove-label", owner_label])
    except GhError as e:
        return fail(str(e))

    print(f"released #{n} from {args.owner}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
