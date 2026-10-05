"""Stdlib unit tests for tool/orchestrator.

Run with: python -m unittest discover -s tool/orchestrator/tests
"""

from __future__ import annotations

import json
import os
import sys
import unittest
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import ci_watch  # noqa: E402
import models  # noqa: E402
import opencode_bridge  # noqa: E402


def fake_proc(returncode=0, stdout="", stderr=""):
    return SimpleNamespace(returncode=returncode, stdout=stdout, stderr=stderr)


class ModelTests(unittest.TestCase):
    ROSTER = ["deepseek/deepseek-v4-flash", "opencode/muse-spark-1.3-contributor-free"]

    def test_role_defaults_resolve(self):
        self.assertEqual(
            models.resolve_model("coder", available=self.ROSTER),
            "opencode/muse-spark-1.3-contributor-free",
        )
        self.assertEqual(
            models.resolve_model("planner", available=self.ROSTER),
            "deepseek/deepseek-v4-flash",
        )

    def test_override_wins(self):
        self.assertEqual(
            models.resolve_model("coder", override="deepseek/deepseek-v4-flash", available=self.ROSTER),
            "deepseek/deepseek-v4-flash",
        )

    def test_unknown_model_rejected(self):
        with self.assertRaises(models.ModelError):
            models.resolve_model("coder", override="nope/model", available=self.ROSTER)

    def test_unknown_role_rejected(self):
        with self.assertRaises(models.ModelError):
            models.resolve_model("wizard", available=self.ROSTER)


class BridgeTests(unittest.TestCase):
    def test_run_iteration_parses_session_id(self):
        def runner(cmd):
            self.assertEqual(cmd[:3], ["opencode", "run", "--agent"])
            return fake_proc(stdout='{"sessionID": "ses_123"}')

        result = opencode_bridge.run_iteration("do work", runner=runner)
        self.assertEqual(result["session_id"], "ses_123")

    def test_run_iteration_raises_on_failure(self):
        with self.assertRaises(opencode_bridge.BridgeError):
            opencode_bridge.run_iteration("x", runner=lambda cmd: fake_proc(returncode=1, stderr="boom"))

    def test_read_session_falls_back_to_db(self):
        calls = []

        def runner(cmd):
            calls.append(cmd)
            if cmd[1] == "export":
                return fake_proc(returncode=1, stderr="no export")
            return fake_proc(stdout='[{"id": "m1"}]')

        data = opencode_bridge.read_session("ses_1", runner=runner)
        self.assertEqual(data, {"messages": [{"id": "m1"}]})
        self.assertEqual(calls[0][1], "export")
        self.assertEqual(calls[1][1], "db")

    def test_summarize_collects_text(self):
        data = {"parts": [{"text": "hello"}, {"text": "world"}, {"n": 1}]}
        self.assertEqual(opencode_bridge.summarize_session(data), "hello\nworld")


class CiWatchTests(unittest.TestCase):
    def test_failing_jobs_filters(self):
        payload = {"jobs": [
            {"name": "Analyze", "conclusion": "failure"},
            {"name": "Build", "conclusion": "success"},
            {"name": "iOS", "conclusion": "cancelled"},
        ]}
        self.assertEqual(ci_watch.failing_jobs(payload), ["Analyze", "iOS"])

    def test_title_has_no_sha(self):
        self.assertEqual(ci_watch.issue_title(), "CI failing on main")

    def test_title_uses_the_given_workflow_name(self):
        self.assertEqual(
            ci_watch.issue_title("Supabase migrate"),
            "Supabase migrate failing on main",
        )

    def test_body_contains_marker_and_sha(self):
        body = ci_watch.issue_body("https://run", "abcdef1234567890", ["Analyze"])
        self.assertIn(ci_watch.MARKER, body)
        self.assertIn("abcdef1234567890", body)
        self.assertIn("Analyze", body)

    def test_labels_for_ci_has_no_ops_label(self):
        self.assertEqual(ci_watch.labels_for("CI"), ["P1", "bug"])

    def test_labels_for_ops_workflow_adds_ops_label(self):
        self.assertEqual(ci_watch.labels_for("Supabase migrate"), ["P1", "bug", "ops"])
        self.assertEqual(ci_watch.labels_for("iOS Release"), ["P1", "bug", "ops"])
        self.assertEqual(ci_watch.labels_for("Play Store Release"), ["P1", "bug", "ops"])
        self.assertEqual(
            ci_watch.labels_for("Supabase Realtime reconciliation"), ["P1", "bug", "ops"]
        )

    def test_recovery_comment_leads_with_its_marker_and_names_the_run(self):
        body = ci_watch.recovery_comment("abcdef1234567890", "https://run", "CI")
        self.assertTrue(body.startswith(ci_watch.RECOVERY_MARKER))
        self.assertIn("`CI` passed on `main` at `abcdef1234567890`", body)
        self.assertIn("https://run", body)
        # It informs; it never claims the cause is known.
        self.assertIn("may be a flake", body)
        self.assertTrue(ci_watch.is_recovery_note(body))

    def test_a_failure_comment_is_not_a_recovery_note(self):
        self.assertFalse(
            ci_watch.is_recovery_note(
                ci_watch.failure_comment("abc", "https://run", after_recovery=False)
            )
        )
        self.assertFalse(ci_watch.is_recovery_note(""))
        self.assertFalse(ci_watch.is_recovery_note(None))

    def test_recovery_is_noted_once_not_on_every_green_run(self):
        """Every success on main runs the watch; only the first after a
        failure may comment."""
        note = {"body": ci_watch.recovery_comment("abc", "https://run")}
        failing = {"body": ci_watch.failure_comment("abc", "https://run", False)}
        self.assertFalse(ci_watch.recovery_noted([]))
        self.assertFalse(ci_watch.recovery_noted([failing]))
        self.assertTrue(ci_watch.recovery_noted([failing, note]))
        # A human reply after the note still counts as "newest is not a note":
        # the next green run notes it again rather than guessing intent.
        self.assertFalse(ci_watch.recovery_noted([note, {"body": "looking"}]))

    def test_a_failure_after_a_recovery_makes_the_next_success_worth_noting(self):
        note = {"body": ci_watch.recovery_comment("abc", "https://run")}
        again = {"body": ci_watch.failure_comment("def", "https://run2", True)}
        self.assertFalse(ci_watch.recovery_noted([note, again]))

    def test_failure_comment_says_again_only_after_a_recovery(self):
        self.assertTrue(
            ci_watch.failure_comment("abc", "https://run", after_recovery=False)
            .startswith("Still failing at `abc`.")
        )
        self.assertTrue(
            ci_watch.failure_comment("abc", "https://run", after_recovery=True)
            .startswith("Failing again at `abc`.")
        )

    def test_find_existing_reuses_the_open_issue_across_shas(self):
        """A new failing SHA on the same workflow comments on the existing
        open issue instead of opening a duplicate per merge."""
        issues = [
            {"number": 2, "body": "no marker"},
            {
                "number": 1,
                "body": f"{ci_watch.MARKER}\n{ci_watch.workflow_marker('CI')}\nsha abcdef1234567890",
            },
        ]
        self.assertEqual(ci_watch.find_existing_number(issues), 1)
        self.assertIsNone(ci_watch.find_existing_number([{"number": 2, "body": "no marker"}]))

    def test_main_comments_on_existing_issue_for_a_new_sha(self):
        env = {
            "RUN_ID": "1",
            "HEAD_SHA": "deadbeef00000000",
            "RUN_URL": "https://run",
            "GITHUB_REPOSITORY": "wjdavis5/lunarlog",
            "HEAD_REPOSITORY": "wjdavis5/lunarlog",
            "HEAD_BRANCH": "main",
            "WORKFLOW_NAME": "Supabase migrate",
        }
        existing = [{
            "number": 7,
            "body": f"{ci_watch.MARKER}\n{ci_watch.workflow_marker('Supabase migrate')}\nsha abcdef1234567890",
        }]

        def fake_run(args, input_text=None):
            if args[0] == "api":
                return '{"jobs": []}'
            if args[:2] == ["issue", "list"]:
                return json.dumps(existing)
            return ""

        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(ci_watch, "_run", side_effect=fake_run) as run_mock:
                self.assertEqual(ci_watch.main(), 0)
        calls = [c.args[0] for c in run_mock.call_args_list]
        self.assertIn(["issue", "comment", "7", "--body", "Still failing at `deadbeef00000000`.\n\nhttps://run"], calls)
        self.assertFalse(any(c[:2] == ["issue", "create"] for c in calls))

    @staticmethod
    def _job(name, conclusion="success", steps=None):
        """A jobs-API job. By default one that really ran: checkout, the
        suite, and an upload step that only runs on failure."""
        if steps is None:
            steps = [
                ("Set up job", "success"),
                ("Check if Flutter tests should run", "success"),
                ("Run actions/checkout", "success"),
                ("Test (with coverage)", conclusion),
                ("Upload failure logs", "skipped"),
                ("Post Run actions/checkout", "success"),
                ("Complete job", "success"),
            ]
        return {
            "name": name,
            "conclusion": conclusion,
            "steps": [{"name": n, "conclusion": c} for n, c in steps],
        }

    @classmethod
    def _gated_job(cls, name):
        """The same job on a push that did not touch its paths: the gate
        step runs, everything after it is skipped, the job is green."""
        return cls._job(name, steps=[
            ("Set up job", "success"),
            ("Check if Flutter tests should run", "success"),
            ("Run actions/checkout", "skipped"),
            ("Test (with coverage)", "skipped"),
            ("Upload failure logs", "skipped"),
            ("Complete job", "success"),
        ])

    def test_named_failing_jobs_reads_back_what_the_watch_writes(self):
        body = ci_watch.issue_body("https://run", "abc", ["Test (shard 0)", "Verify"])
        self.assertEqual(ci_watch.named_failing_jobs(body), ["Test (shard 0)", "Verify"])
        comment = ci_watch.failure_comment("abc", "https://run", False, ["iOS"])
        self.assertEqual(ci_watch.named_failing_jobs(comment), ["iOS"])
        # Nothing recorded, nothing read back -- and the triage lines after
        # the list are not mistaken for job names.
        self.assertEqual(
            ci_watch.named_failing_jobs(ci_watch.issue_body("https://run", "abc", [])), []
        )
        self.assertEqual(ci_watch.named_failing_jobs(""), [])
        self.assertEqual(ci_watch.named_failing_jobs(None), [])

    def test_a_failure_comment_without_jobs_is_unchanged(self):
        self.assertEqual(
            ci_watch.failure_comment("abc", "https://run", False),
            "Still failing at `abc`.\n\nhttps://run",
        )
        self.assertEqual(
            ci_watch.failure_comment("abc", "https://run", False, []),
            "Still failing at `abc`.\n\nhttps://run",
        )

    def test_a_job_that_ran_its_suite_did_work(self):
        self.assertTrue(ci_watch.job_did_work(self._job("Test (shard 0)")))
        # No step detail: the job's own conclusion is all there is.
        self.assertTrue(ci_watch.job_did_work({"name": "x", "conclusion": "success"}))
        # A single real step and nothing skipped (an ungated workflow).
        self.assertTrue(ci_watch.job_did_work(
            self._job("migrate", steps=[("Set up job", "success"), ("db push", "success")])
        ))

    def test_a_job_with_no_gate_is_taken_at_its_conclusion(self):
        # "CI required checks" as the jobs API reports it on a green run:
        # one real step, and a failure-only step that is skipped. It has no
        # path-filter gate, so the skipped step says nothing.
        required = self._job("CI required checks", steps=[
            ("Set up job", "success"),
            ("Report required job results", "success"),
            ("Fail unless every required job succeeded", "skipped"),
            ("Complete job", "success"),
        ])
        self.assertTrue(ci_watch.job_did_work(required))

    def test_the_gate_step_is_recognised_by_its_name(self):
        self.assertTrue(ci_watch.is_gate_step("Check if Flutter tests should run"))
        self.assertTrue(ci_watch.is_gate_step("Check if the web app should run"))
        self.assertFalse(ci_watch.is_gate_step("Check internal links"))
        self.assertFalse(ci_watch.is_gate_step("Report required job results"))
        self.assertFalse(ci_watch.is_gate_step(""))
        self.assertFalse(ci_watch.is_gate_step(None))

    def test_a_gated_job_whose_suite_ran_did_work(self):
        # The gate said run: steps after it executed, with only the
        # failure-only upload skipped.
        self.assertTrue(ci_watch.job_did_work(self._job("Test (shard 0)")))

    def test_a_path_filtered_job_did_no_work_although_it_is_green(self):
        gated = self._gated_job("Test (shard 0)")
        self.assertEqual(gated["conclusion"], "success")
        self.assertFalse(ci_watch.job_did_work(gated))

    def test_a_failed_or_skipped_job_did_no_work(self):
        self.assertFalse(ci_watch.job_did_work(self._job("Test (shard 0)", "failure")))
        self.assertFalse(ci_watch.job_did_work({"name": "x", "conclusion": "skipped"}))
        self.assertFalse(ci_watch.job_did_work({"name": "x", "conclusion": None}))

    def test_a_green_run_is_a_recovery_only_when_the_failed_jobs_ran(self):
        ran = {"jobs": [self._job("Test (shard 0)"), self._gated_job("Site")]}
        self.assertTrue(ci_watch.recovery_verdict(["Test (shard 0)"], ran)[0])

        skipped = {"jobs": [self._gated_job("Test (shard 0)"), self._job("Site")]}
        recovered, reason = ci_watch.recovery_verdict(["Test (shard 0)"], skipped)
        self.assertFalse(recovered)
        self.assertIn("Test (shard 0)", reason)

        # One of two failed suites re-ran: still not a recovery.
        half = {"jobs": [self._job("Test (shard 0)"), self._gated_job("Verify")]}
        self.assertFalse(ci_watch.recovery_verdict(["Test (shard 0)", "Verify"], half)[0])

        # The failed job is not in this run at all.
        self.assertFalse(
            ci_watch.recovery_verdict(["Renamed job"], {"jobs": [self._job("Other")]})[0]
        )

    def test_with_no_failed_jobs_on_record_every_job_must_have_run(self):
        self.assertTrue(
            ci_watch.recovery_verdict([], {"jobs": [self._job("a"), self._job("b")]})[0]
        )
        self.assertFalse(
            ci_watch.recovery_verdict([], {"jobs": [self._job("a"), self._gated_job("b")]})[0]
        )

    def test_unreadable_jobs_are_never_a_recovery(self):
        self.assertFalse(ci_watch.recovery_verdict(["a"], {"jobs": []})[0])
        self.assertFalse(ci_watch.recovery_verdict(["a"], {})[0])
        self.assertFalse(ci_watch.recovery_verdict([], None)[0])

    def test_failed_jobs_on_record_follow_the_incident(self):
        body = ci_watch.issue_body("https://run", "abc", ["Test (shard 0)"])
        later = {"body": ci_watch.failure_comment("def", "https://run2", False, ["Verify"])}
        chatter = {"body": "looking into it"}
        self.assertEqual(
            ci_watch.failed_jobs_on_record(body, [chatter, later]),
            ["Test (shard 0)", "Verify"],
        )
        # A noted recovery closed the first incident: only what failed
        # after it is outstanding.
        note = {"body": ci_watch.recovery_comment("ghi", "https://run3")}
        again = {"body": ci_watch.failure_comment("jkl", "https://run4", True, ["iOS"])}
        self.assertEqual(ci_watch.failed_jobs_on_record(body, [later, note, again]), ["iOS"])

    def _run_main(self, conclusion, comments, has_issue=True, jobs=None, failed=None):
        """Drives main() for the CI workflow against a faked `gh`, with an
        open rolling issue #7 (unless told otherwise) carrying [comments].
        [failed] are the job names the issue body records; [jobs] is what
        the run's jobs API answers."""
        env = {
            "RUN_ID": "1",
            "HEAD_SHA": "deadbeef00000000",
            "RUN_URL": "https://run",
            "GITHUB_REPOSITORY": "wjdavis5/lunarlog",
            "HEAD_REPOSITORY": "wjdavis5/lunarlog",
            "HEAD_BRANCH": "main",
            "WORKFLOW_NAME": "CI",
            "RUN_CONCLUSION": conclusion,
        }
        existing = [{
            "number": 7,
            "body": ci_watch.issue_body("https://first", "0000", failed or [], "CI"),
        }] if has_issue else []

        def fake_run(args, input_text=None):
            if args[0] == "api":
                return json.dumps({"jobs": jobs or []})
            if args[:2] == ["issue", "list"]:
                return json.dumps(existing)
            if args[:2] == ["issue", "view"]:
                return json.dumps({"comments": comments})
            return ""

        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(ci_watch, "_run", side_effect=fake_run) as run_mock:
                self.assertEqual(ci_watch.main(), 0)
        return [c.args[0] for c in run_mock.call_args_list]

    def test_main_notes_a_recovery_when_the_failed_suite_ran_and_passed(self):
        calls = self._run_main(
            "success",
            comments=[{"body": "Still failing at `abc`.\n\nhttps://old"}],
            failed=["Test (shard 0)"],
            jobs=[self._job("Test (shard 0)"), self._gated_job("Site")],
        )
        comments = [c for c in calls if c[:2] == ["issue", "comment"]]
        self.assertEqual(len(comments), 1)
        self.assertEqual(comments[0][2], "7")
        self.assertTrue(ci_watch.is_recovery_note(comments[0][4]))
        self.assertIn("deadbeef00000000", comments[0][4])
        # A pass never files or closes.
        self.assertFalse(any(c[:2] == ["issue", "create"] for c in calls))
        self.assertFalse(any(c[:2] == ["issue", "close"] for c in calls))

    def test_main_says_nothing_when_the_green_run_skipped_the_failed_suite(self):
        # Issue #1437: a docs-only merge. CI is green, and the Flutter shard
        # that broke `main` never ran.
        calls = self._run_main(
            "success",
            comments=[],
            failed=["Test (shard 0)"],
            jobs=[self._gated_job("Test (shard 0)"), self._job("Site")],
        )
        self.assertFalse(any(c[:2] == ["issue", "comment"] for c in calls))
        self.assertFalse(any(c[:2] == ["issue", "close"] for c in calls))

    def test_main_checks_the_jobs_a_later_failure_recorded_too(self):
        later = {"body": ci_watch.failure_comment("def", "https://run2", False, ["Verify"])}
        calls = self._run_main(
            "success",
            comments=[later],
            failed=["Test (shard 0)"],
            jobs=[self._job("Test (shard 0)"), self._gated_job("Verify")],
        )
        self.assertFalse(any(c[:2] == ["issue", "comment"] for c in calls))

    def test_main_records_the_failing_jobs_on_a_further_failure(self):
        calls = self._run_main(
            "failure",
            comments=[],
            failed=["Test (shard 0)"],
            jobs=[self._job("Verify", "failure")],
        )
        comment = next(c for c in calls if c[:2] == ["issue", "comment"])
        self.assertEqual(ci_watch.named_failing_jobs(comment[4]), ["Verify"])
        self.assertTrue(comment[4].startswith("Still failing at `deadbeef00000000`."))

    def test_main_does_not_repeat_a_recovery_note(self):
        calls = self._run_main("success", comments=[
            {"body": ci_watch.recovery_comment("abc", "https://old")},
        ])
        self.assertFalse(any(c[:2] == ["issue", "comment"] for c in calls))

    def test_main_does_nothing_on_a_pass_with_no_open_issue(self):
        calls = self._run_main("success", comments=[], has_issue=False)
        self.assertEqual([c[:2] for c in calls], [["issue", "list"]])

    def test_main_says_failing_again_after_a_noted_recovery(self):
        calls = self._run_main("failure", comments=[
            {"body": ci_watch.recovery_comment("abc", "https://old")},
        ])
        self.assertIn(
            ["issue", "comment", "7", "--body",
             "Failing again at `deadbeef00000000`.\n\nhttps://run"],
            calls,
        )

    def test_is_trusted_source_accepts_the_repos_own_main(self):
        self.assertTrue(
            ci_watch.is_trusted_source("wjdavis5/lunarlog", "wjdavis5/lunarlog", "main")
        )

    def test_is_trusted_source_rejects_a_fork_branch_named_main(self):
        """LLA-114: a PR opened straight from a fork's own "main" branch
        must not be mistaken for this repository's own main failing --
        head_repository differs from repo even though head_branch matches."""
        self.assertFalse(
            ci_watch.is_trusted_source("wjdavis5/lunarlog", "someforker/lunarlog", "main")
        )

    def test_is_trusted_source_rejects_a_non_main_branch_even_from_this_repo(self):
        self.assertFalse(
            ci_watch.is_trusted_source(
                "wjdavis5/lunarlog", "wjdavis5/lunarlog", "some-feature-branch"
            )
        )

    def test_is_trusted_source_rejects_missing_fields(self):
        self.assertFalse(ci_watch.is_trusted_source("wjdavis5/lunarlog", "", "main"))
        self.assertFalse(ci_watch.is_trusted_source("wjdavis5/lunarlog", "wjdavis5/lunarlog", ""))
        self.assertFalse(ci_watch.is_trusted_source("", "wjdavis5/lunarlog", "main"))

    def test_main_skips_filing_for_an_untrusted_fork_run(self):
        """End-to-end LLA-114 regression: main() must return 0 without
        shelling out to `gh` at all -- a fork's own "main" branch failing
        must never touch the issue tracker."""
        env = {
            "RUN_ID": "1",
            "HEAD_SHA": "abcdef1234567890",
            "RUN_URL": "https://run",
            "GITHUB_REPOSITORY": "wjdavis5/lunarlog",
            "HEAD_REPOSITORY": "someforker/lunarlog",
            "HEAD_BRANCH": "main",
            "WORKFLOW_NAME": "CI",
        }
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(ci_watch, "_run") as run_mock:
                self.assertEqual(ci_watch.main(), 0)
                run_mock.assert_not_called()

    def test_find_existing_scopes_by_workflow(self):
        """Two different workflows failing on the same SHA must not collide
        into one issue (issue #537: ops failures triage separately)."""
        issues = [
            {
                "number": 1,
                "body": f"{ci_watch.MARKER}\n{ci_watch.workflow_marker('CI')}\nsha abcdef1234567890",
            },
        ]
        self.assertEqual(ci_watch.find_existing_number(issues, "CI"), 1)
        self.assertIsNone(ci_watch.find_existing_number(issues, "Supabase migrate"))


if __name__ == "__main__":
    unittest.main()
