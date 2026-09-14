"""Stdlib unit tests for tool/orchestrator.

Run with: python -m unittest discover -s tool/orchestrator/tests
"""

from __future__ import annotations

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

    def test_title_uses_short_sha(self):
        self.assertEqual(ci_watch.issue_title("abcdef1234567890"), "CI failing on main at abcdef1")

    def test_title_uses_the_given_workflow_name(self):
        self.assertEqual(
            ci_watch.issue_title("abcdef1234567890", "Supabase migrate"),
            "Supabase migrate failing on main at abcdef1",
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

    def test_find_existing_matches_full_sha_only(self):
        issues = [
            {
                "number": 1,
                "body": f"{ci_watch.MARKER}\n{ci_watch.workflow_marker('CI')}\nsha abcdef1234567890",
            },
            {"number": 2, "body": "no marker"},
        ]
        self.assertEqual(ci_watch.find_existing_number(issues, "abcdef1234567890"), 1)
        self.assertIsNone(ci_watch.find_existing_number(issues, "deadbeef00000000"))

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
        self.assertEqual(ci_watch.find_existing_number(issues, "abcdef1234567890", "CI"), 1)
        self.assertIsNone(
            ci_watch.find_existing_number(issues, "abcdef1234567890", "Supabase migrate")
        )


if __name__ == "__main__":
    unittest.main()
