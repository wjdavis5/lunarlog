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


# Issue #537: `ci-failure-watch.yml` now watches CI plus every ops/release
# workflow (Supabase migrate, Supabase Realtime reconciliation, iOS Release,
# Play Store Release). These distinguish themselves from ordinary app-CI
# failures with a dedicated label so they triage on a separate track instead
# of blending into the regular CI-red backlog.
OPS_WORKFLOWS = {
    "Supabase migrate",
    "Supabase Realtime reconciliation",
    "iOS Release",
    "Play Store Release",
}


def short_sha(head_sha: str) -> str:
    return (head_sha or "")[:7]


def workflow_marker(workflow_name: str) -> str:
    return f"<!-- workflow: {workflow_name} -->"


def issue_title(head_sha: str, workflow_name: str = "CI") -> str:
    return f"{workflow_name} failing on main at {short_sha(head_sha)}"


def labels_for(workflow_name: str) -> list[str]:
    labels = ["P1", "bug"]
    if workflow_name in OPS_WORKFLOWS:
        labels.append("ops")
    return labels


def failing_jobs(jobs_payload: dict) -> list[str]:
    return [
        job.get("name", "unknown")
        for job in (jobs_payload or {}).get("jobs", [])
        if (job.get("conclusion") or "").lower() in FAIL_CONCLUSIONS
    ]


def issue_body(run_url: str, head_sha: str, jobs: list[str], workflow_name: str = "CI") -> str:
    lines = [
        MARKER,
        workflow_marker(workflow_name),
        f"`{workflow_name}` failed on `main` at `{head_sha}`.",
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


def find_existing_number(issues: list[dict], head_sha: str, workflow_name: str = "CI") -> int | None:
    """Match on the marker plus the full SHA plus the workflow marker, so a
    different failing SHA on the same short prefix does not collide, and two
    different workflows failing on the same SHA get their own issues instead
    of one triage stream drowning the other."""
    marker = workflow_marker(workflow_name)
    for issue in issues:
        body = issue.get("body") or ""
        if MARKER in body and head_sha in body and marker in body:
            return issue.get("number")
    return None


def main() -> int:
    run_id = os.environ.get("RUN_ID")
    head_sha = os.environ.get("HEAD_SHA")
    run_url = os.environ.get("RUN_URL")
    repo = os.environ.get("GITHUB_REPOSITORY")
    workflow_name = os.environ.get("WORKFLOW_NAME") or "CI"
    if not (run_id and head_sha and run_url and repo):
        print("error: RUN_ID, HEAD_SHA, RUN_URL, GITHUB_REPOSITORY are required", file=sys.stderr)
        return 2

    try:
        jobs_payload = json.loads(
            _run(["api", f"repos/{repo}/actions/runs/{run_id}/jobs"])
        )
        jobs = failing_jobs(jobs_payload)
        body = issue_body(run_url, head_sha, jobs, workflow_name)
        existing = json.loads(
            _run([
                "issue", "list", "--state", "open", "--limit", "100",
                "--json", "number,body",
            ])
        )
        number = find_existing_number(existing, head_sha, workflow_name)
        if number:
            _run(["issue", "comment", str(number), "--body", f"Still failing at `{head_sha}`.\n\n{run_url}"])
            print(f"updated issue #{number}")
        else:
            args = [
                "issue", "create",
                "--title", issue_title(head_sha, workflow_name),
                "--body", body,
            ]
            for label in labels_for(workflow_name):
                args += ["--label", label]
            out = _run(args)
            print(out.strip())
    except (WatchError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
