"""Stdlib unit tests for tool/orchestrator.

Run with: python -m unittest discover -s tool/orchestrator/tests
"""

from __future__ import annotations

import os
import sys
import unittest
from types import SimpleNamespace

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

    def test_body_contains_marker_and_sha(self):
        body = ci_watch.issue_body("https://run", "abcdef1234567890", ["Analyze"])
        self.assertIn(ci_watch.MARKER, body)
        self.assertIn("abcdef1234567890", body)
        self.assertIn("Analyze", body)

    def test_find_existing_matches_full_sha_only(self):
        issues = [
            {"number": 1, "body": f"{ci_watch.MARKER}\nsha abcdef1234567890"},
            {"number": 2, "body": "no marker"},
        ]
        self.assertEqual(ci_watch.find_existing_number(issues, "abcdef1234567890"), 1)
        self.assertIsNone(ci_watch.find_existing_number(issues, "deadbeef00000000"))


if __name__ == "__main__":
    unittest.main()
