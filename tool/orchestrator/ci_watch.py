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


FAILING_JOBS_HEADING = "Failing jobs:"

# Steps the runner adds to every job. They succeed whether or not the job's
# own steps ran, so they say nothing about whether it did any work.
_BOOKKEEPING_STEPS = ("Set up job", "Complete job")
_BOOKKEEPING_PREFIXES = ("Post ", "Pre ")


def failing_jobs_block(jobs: list[str]) -> list[str]:
    """The lines that record which jobs failed. [named_failing_jobs] reads
    them back, so the two must stay in step."""
    return [FAILING_JOBS_HEADING] + [f"- `{name}`" for name in jobs]


def named_failing_jobs(text: str) -> list[str]:
    """The job names recorded under "Failing jobs:" in an issue body or a
    failure comment, in order, without duplicates."""
    names: list[str] = []
    in_block = False
    for raw in (text or "").splitlines():
        line = raw.strip()
        if line == FAILING_JOBS_HEADING:
            in_block = True
            continue
        if not in_block:
            continue
        if line.startswith("- `") and line.endswith("`") and len(line) > 4:
            name = line[3:-1]
            if name not in names:
                names.append(name)
        else:
            in_block = False
    return names


def is_gate_step(step_name: str) -> bool:
    """CI's path-filter gate: every gated job opens with a step named
    "Check if <suite> should run"."""
    name = step_name or ""
    return name.startswith("Check if ") and name.endswith(" should run")


def job_did_work(job: dict) -> bool:
    """True when a job concluded `success` and actually ran its steps.

    CI on a push to `main` path-filters: a suite whose paths did not change
    still starts its job, runs its gate step ("Check if ... should run"),
    skips every step after it, and concludes `success`. Such a job proves
    nothing about the suite.

    The gate step is what marks that case. A job with no gate is taken at
    its conclusion, however many of its steps were skipped: "CI required
    checks", for one, has a single real step and a failure-only step that
    is skipped on every green run.
    """
    if (job.get("conclusion") or "").lower() != "success":
        return False
    steps = [
        step for step in (job.get("steps") or [])
        if (step.get("name") or "") not in _BOOKKEEPING_STEPS
        and not (step.get("name") or "").startswith(_BOOKKEEPING_PREFIXES)
    ]
    gate = next(
        (index for index, step in enumerate(steps) if is_gate_step(step.get("name") or "")),
        None,
    )
    if gate is None:
        return True
    after = steps[gate + 1:]
    if not after:
        return True
    return any((step.get("conclusion") or "").lower() != "skipped" for step in after)


def recovery_verdict(failed_names: list[str], jobs_payload: dict) -> tuple[bool, str]:
    """Whether a successful run is evidence that the failure is gone.

    It is only when every job that failed ran again for real and passed.
    When the failed jobs are not on record, every job in the run has to
    have done real work. Anything short of that returns False with the
    reason: a missed recovery note costs little, a false one invites
    someone to close a live failure.
    """
    jobs = (jobs_payload or {}).get("jobs") or []
    if not jobs:
        return False, "the run's jobs could not be read"
    by_name = {job.get("name"): job for job in jobs}
    if failed_names:
        for name in failed_names:
            job = by_name.get(name)
            if job is None:
                return False, f"`{name}` was not part of this run"
            if not job_did_work(job):
                return False, f"`{name}` did not run its suite in this run"
        return True, "every job that failed ran and passed"
    for job in jobs:
        if not job_did_work(job):
            return False, f"`{job.get('name', 'unknown')}` did not run its suite in this run"
    return True, "every job in the run did its work and passed"


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
        lines += failing_jobs_block(jobs)
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


def failure_comment(
    head_sha: str, run_url: str, after_recovery: bool, jobs: list[str] | None = None
) -> str:
    """The comment a further failure leaves on the open rolling issue.

    It records which jobs failed this time. A later failure can be in a
    different suite from the one that opened the issue, and the recovery
    check reads these names back.
    """
    lead = "Failing again" if after_recovery else "Still failing"
    text = f"{lead} at `{head_sha}`.\n\n{run_url}"
    if jobs:
        text += "\n\n" + "\n".join(failing_jobs_block(jobs))
    return text


def _open_issue(workflow_name: str) -> dict | None:
    existing = json.loads(
        _run([
            "issue", "list", "--state", "open", "--limit", "100",
            "--json", "number,body",
        ])
    )
    number = find_existing_number(existing, workflow_name)
    if not number:
        return None
    return next(issue for issue in existing if issue.get("number") == number)


def _open_issue_number(workflow_name: str) -> int | None:
    issue = _open_issue(workflow_name)
    return issue.get("number") if issue else None


def failed_jobs_on_record(issue_body_text: str, comments: list[dict]) -> list[str]:
    """Every job the watch has recorded as failing since the last recovery
    note: the issue body's list plus each later failure comment's."""
    names = named_failing_jobs(issue_body_text)
    last_recovery = max(
        (index for index, comment in enumerate(comments)
         if is_recovery_note(comment.get("body") or "")),
        default=-1,
    )
    if last_recovery >= 0:
        # A noted recovery closed the earlier incident; only what failed
        # after it is still outstanding.
        names = []
    for comment in comments[last_recovery + 1:]:
        for name in named_failing_jobs(comment.get("body") or ""):
            if name not in names:
                names.append(name)
    return names


def _comments(number: int) -> list[dict]:
    raw = _run(["issue", "view", str(number), "--json", "comments"]).strip()
    # Nothing readable means "no recovery note seen": the failure path must
    # never be held up by this lookup.
    if not raw:
        return []
    return json.loads(raw).get("comments") or []


def note_recovery(
    head_sha: str, run_url: str, workflow_name: str, repo: str, run_id: str
) -> str:
    """Handle a successful run: note it on the open rolling issue, once,
    and only when the run re-tested what failed.

    A green run is not always a recovery. CI on `main` skips every suite
    the push did not touch, so a docs-only merge is green over a Flutter
    break that was never re-run (issue #1437). Saying "passed" there would
    invite someone to close a live failure, so that case says nothing.
    """
    issue = _open_issue(workflow_name)
    if not issue:
        return f"no open issue for {workflow_name}; nothing to note"
    number = issue.get("number")
    comments = _comments(number)
    if recovery_noted(comments):
        return f"issue #{number} already notes the recovery"
    jobs_payload = json.loads(
        _run(["api", f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100"]) or "{}"
    )
    recovered, reason = recovery_verdict(
        failed_jobs_on_record(issue.get("body") or "", comments), jobs_payload
    )
    if not recovered:
        return f"green, but not a recovery for issue #{number}: {reason}"
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
            print(note_recovery(head_sha, run_url, workflow_name, repo, run_id))
            return 0
        jobs_payload = json.loads(
            _run(["api", f"repos/{repo}/actions/runs/{run_id}/jobs"])
        )
        jobs = failing_jobs(jobs_payload)
        body = issue_body(run_url, head_sha, jobs, workflow_name)
        number = _open_issue_number(workflow_name)
        if number:
            comment = failure_comment(
                head_sha, run_url,
                after_recovery=recovery_noted(_comments(number)),
                jobs=jobs,
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
