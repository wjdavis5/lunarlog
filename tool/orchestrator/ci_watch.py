"""Turn a failed `CI` run on `main` into one prioritized issue.

Invoked by `.github/workflows/ci-failure-watch.yml` on a `workflow_run`
completion for `main`. A failure creates one rolling issue per workflow, or
comments on the existing one, so a flapping main does not spam the backlog.
A success notes the recovery on that issue, once, so an open "failing on
main" issue never outlives the failure unremarked.

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
# Leads every recovery comment, so the next run can tell "already noted"
# from "still needs noting" without parsing prose.
RECOVERY_MARKER = "<!-- ci-failure-watch: recovered -->"


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


def is_trusted_source(repo: str, head_repository: str, head_branch: str) -> bool:
    """True only when the workflow_run's code actually came from this
    repository's own `main` (LLA-114) -- not a fork whose own default
    branch happens to also be named "main".

    The workflow's `branches: [main]` trigger filter matches on
    `head_branch` alone, and `head_branch` is attacker-controlled: a
    contributor's fork almost always has its own branch named "main" (a
    fork's default branch keeps the upstream default's name), so a PR
    opened straight from that branch produces a `workflow_run` whose
    `head_branch` is "main" even though the code -- and the failure -- has
    nothing to do with this repository's real main. `head_repository` is
    the repo the run's code actually came from, which differs from `repo`
    for exactly that fork-PR shape; requiring the two to match is what
    actually rules a fork out. `head_branch` is re-checked here too,
    redundantly with the workflow trigger's own filter, so this one
    function is a complete, independently testable gate rather than
    something that silently relies on the YAML filter never drifting out
    of sync with it.
    """
    return bool(repo) and bool(head_repository) and repo == head_repository and head_branch == "main"


def short_sha(head_sha: str) -> str:
    return (head_sha or "")[:7]


def workflow_marker(workflow_name: str) -> str:
    return f"<!-- workflow: {workflow_name} -->"


def issue_title(workflow_name: str = "CI") -> str:
    # One rolling issue per workflow, not per SHA: every merge to main is a new
    # SHA, so a SHA in the title/dedupe key opened a fresh duplicate issue for
    # each still-failing run (six "Supabase migrate failing on main at <sha>"
    # issues in one day, all the same root cause).
    return f"{workflow_name} failing on main"


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


def find_existing_number(issues: list[dict], workflow_name: str = "CI") -> int | None:
    """Match on the watch marker plus the workflow marker only: any open
    issue for this workflow absorbs further failures as comments, whatever
    SHA they are at, while two different workflows still get their own
    issues instead of one triage stream drowning the other."""
    marker = workflow_marker(workflow_name)
    for issue in issues:
        body = issue.get("body") or ""
        if MARKER in body and marker in body:
            return issue.get("number")
    return None


def is_recovery_note(comment_body: str) -> bool:
    return (comment_body or "").lstrip().startswith(RECOVERY_MARKER)


def recovery_noted(comments: list[dict]) -> bool:
    """True when the issue's newest comment is already a recovery note.

    Every success on `main` runs the watch, so without this an open issue
    would collect one "passing again" comment per merge. Only the newest
    comment counts: a failure after a recovery adds a newer comment, which
    makes the next success worth noting again.
    """
    if not comments:
        return False
    return is_recovery_note(comments[-1].get("body") or "")


def recovery_comment(head_sha: str, run_url: str, workflow_name: str = "CI") -> str:
    """The one comment a recovered workflow leaves on its rolling issue.

    It does not close the issue. A pass can be a flake going quiet as easily
    as a fix, and the issue body tells the reader not to accept green without
    a cause; closing is the triager's call. What this does is stop the issue
    from reading as a live outage when it is not.
    """
    return "\n".join([
        RECOVERY_MARKER,
        f"`{workflow_name}` passed on `main` at `{head_sha}`.",
        "",
        f"Run: {run_url}",
        "",
        "Close this if the failure is understood. If it is not, it is still",
        "open for triage: a pass without a known cause may be a flake.",
    ])


def failure_comment(head_sha: str, run_url: str, after_recovery: bool) -> str:
    """The comment a further failure leaves on the open rolling issue."""
    lead = "Failing again" if after_recovery else "Still failing"
    return f"{lead} at `{head_sha}`.\n\n{run_url}"


def _open_issue_number(workflow_name: str) -> int | None:
    existing = json.loads(
        _run([
            "issue", "list", "--state", "open", "--limit", "100",
            "--json", "number,body",
        ])
    )
    return find_existing_number(existing, workflow_name)


def _comments(number: int) -> list[dict]:
    raw = _run(["issue", "view", str(number), "--json", "comments"]).strip()
    # Nothing readable means "no recovery note seen": the failure path must
    # never be held up by this lookup.
    if not raw:
        return []
    return json.loads(raw).get("comments") or []


def note_recovery(head_sha: str, run_url: str, workflow_name: str) -> str:
    """Handle a successful run: note it on the open rolling issue, once."""
    number = _open_issue_number(workflow_name)
    if not number:
        return f"no open issue for {workflow_name}; nothing to note"
    if recovery_noted(_comments(number)):
        return f"issue #{number} already notes the recovery"
    _run([
        "issue", "comment", str(number),
        "--body", recovery_comment(head_sha, run_url, workflow_name),
    ])
    return f"noted the recovery on issue #{number}"


def main() -> int:
    run_id = os.environ.get("RUN_ID")
    head_sha = os.environ.get("HEAD_SHA")
    run_url = os.environ.get("RUN_URL")
    repo = os.environ.get("GITHUB_REPOSITORY")
    head_repository = os.environ.get("HEAD_REPOSITORY")
    head_branch = os.environ.get("HEAD_BRANCH")
    workflow_name = os.environ.get("WORKFLOW_NAME") or "CI"
    # "failure" when unset, so a caller that predates the recovery path
    # behaves exactly as before.
    conclusion = (os.environ.get("RUN_CONCLUSION") or "failure").lower()
    if not (run_id and head_sha and run_url and repo and head_repository and head_branch):
        print(
            "error: RUN_ID, HEAD_SHA, RUN_URL, GITHUB_REPOSITORY, HEAD_REPOSITORY, "
            "HEAD_BRANCH are required",
            file=sys.stderr,
        )
        return 2

    # LLA-114: never let a fork's identically-named branch pose as this
    # repository's own main failing -- see is_trusted_source's docstring.
    if not is_trusted_source(repo, head_repository, head_branch):
        print(
            f"skipping: workflow_run's code came from '{head_repository}' "
            f"branch '{head_branch}', not {repo}'s own main; not filing an "
            "issue (LLA-114)."
        )
        return 0

    try:
        if conclusion == "success":
            print(note_recovery(head_sha, run_url, workflow_name))
            return 0
        jobs_payload = json.loads(
            _run(["api", f"repos/{repo}/actions/runs/{run_id}/jobs"])
        )
        jobs = failing_jobs(jobs_payload)
        body = issue_body(run_url, head_sha, jobs, workflow_name)
        number = _open_issue_number(workflow_name)
        if number:
            comment = failure_comment(
                head_sha, run_url, after_recovery=recovery_noted(_comments(number))
            )
            _run(["issue", "comment", str(number), "--body", comment])
            print(f"updated issue #{number}")
        else:
            args = [
                "issue", "create",
                "--title", issue_title(workflow_name),
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
