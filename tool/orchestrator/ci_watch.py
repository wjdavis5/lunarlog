"""Turn a failed `CI` run on `main` into one prioritized issue.

Invoked by `.github/workflows/ci-failure-watch.yml` on a `workflow_run`
completion for `main`. Creates one issue per failing head SHA, or comments on
the existing one, so a flapping main does not spam the backlog.

Pure builders are unit-tested; `main` is the thin `gh`-calling wrapper.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

FAIL_CONCLUSIONS = {
    "failure", "timed_out", "cancelled", "action_required", "startup_failure",
}
MARKER = "<!-- ci-failure-watch -->"


class WatchError(RuntimeError):
    """A gh call or input failed."""


def _run(args: list[str], input_text: str | None = None) -> str:
    proc = subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        input=input_text,
        timeout=90,
    )
    if proc.returncode != 0:
        raise WatchError(f"gh {' '.join(args[:2])} failed: {(proc.stderr or '').strip()}")
    return proc.stdout


def short_sha(head_sha: str) -> str:
    return (head_sha or "")[:7]


def issue_title(head_sha: str) -> str:
    return f"CI failing on main at {short_sha(head_sha)}"


def failing_jobs(jobs_payload: dict) -> list[str]:
    return [
        job.get("name", "unknown")
        for job in (jobs_payload or {}).get("jobs", [])
        if (job.get("conclusion") or "").lower() in FAIL_CONCLUSIONS
    ]


def issue_body(run_url: str, head_sha: str, jobs: list[str]) -> str:
    lines = [
        MARKER,
        f"`CI` failed on `main` at `{head_sha}`.",
        "",
        f"Run: {run_url}",
        "",
    ]
    if jobs:
        lines.append("Failing jobs:")
        lines += [f"- `{name}`" for name in jobs]
    else:
        lines.append("No failing job could be identified from the run's jobs API.")
    lines += [
        "",
        "Triage: reproduce on the head SHA, find the root cause, and file or link the",
        "fix. Do not re-run to green without a fix.",
    ]
    return "\n".join(lines)


def find_existing_number(issues: list[dict], head_sha: str) -> int | None:
    """Match on the marker plus the full SHA, so a different failing SHA on the
    same short prefix does not collide."""
    for issue in issues:
        body = issue.get("body") or ""
        if MARKER in body and head_sha in body:
            return issue.get("number")
    return None


def main() -> int:
    run_id = os.environ.get("RUN_ID")
    head_sha = os.environ.get("HEAD_SHA")
    run_url = os.environ.get("RUN_URL")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not (run_id and head_sha and run_url and repo):
        print("error: RUN_ID, HEAD_SHA, RUN_URL, GITHUB_REPOSITORY are required", file=sys.stderr)
        return 2

    try:
        jobs_payload = json.loads(
            _run(["api", f"repos/{repo}/actions/runs/{run_id}/jobs"])
        )
        jobs = failing_jobs(jobs_payload)
        body = issue_body(run_url, head_sha, jobs)
        existing = json.loads(
            _run([
                "issue", "list", "--state", "open", "--limit", "100",
                "--json", "number,body",
            ])
        )
        number = find_existing_number(existing, head_sha)
        if number:
            _run(["issue", "comment", str(number), "--body", f"Still failing at `{head_sha}`.\n\n{run_url}"])
            print(f"updated issue #{number}")
        else:
            out = _run([
                "issue", "create",
                "--title", issue_title(head_sha),
                "--body", body,
                "--label", "P1", "--label", "bug",
            ])
            print(out.strip())
    except (WatchError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
