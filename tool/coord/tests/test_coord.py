"""Stdlib unit tests for tool/coord's ownership and status helpers.

Run with: python -m unittest discover -s tool/coord/tests
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import claim  # noqa: E402
import list_issues  # noqa: E402
import pr_status  # noqa: E402
import worktree_add  # noqa: E402
from _common import GhError, under, validate_owner, validate_slug  # noqa: E402


class ValidationTests(unittest.TestCase):
    def test_owner_accepts_safe_ids(self):
        for owner in ("opencode-muse", "claude-orch", "a1"):
            self.assertEqual(validate_owner(owner), owner)

    def test_owner_rejects_escape_and_separators(self):
        for owner in ("..", "../x", "a/b", "a\\b", "", "A", "with space", "a.b"):
            with self.assertRaises(GhError):
                validate_owner(owner)

    def test_slug_rejects_path_traversal(self):
        for slug in ("..", "a/b", "a\\b", "", "a b", "a.b"):
            with self.assertRaises(GhError):
                validate_slug(slug)

    def test_under_pins_to_prefix(self):
        root = Path("/repo/.worktrees/opencode-muse")
        self.assertTrue(under(root / "7-foo", root))
        self.assertFalse(under(Path("/repo/.worktrees/claude-orch/7-foo"), root))
        self.assertFalse(under(Path("/repo"), root))


class WorktreeAddTests(unittest.TestCase):
    def test_bad_owner_fails_before_touching_git(self):
        called = []
        worktree_add.repo_root = lambda: (_ for _ in ()).throw(AssertionError("git touched"))
        worktree_add.run_git = lambda *a, **k: called.append(a)
        old = sys.argv
        sys.argv = ["worktree_add.py", "7", "foo", "--owner", ".."]
        try:
            rc = worktree_add.main()
        finally:
            sys.argv = old
        self.assertEqual(rc, 2)
        self.assertEqual(called, [])


class CiRollupTests(unittest.TestCase):
    def _pr(self, *states):
        return {"statusCheckRollup": [{"conclusion": s} for s in states]}

    def test_success_and_skipped_are_green(self):
        self.assertEqual(pr_status.ci_rollup(self._pr("SUCCESS", "SKIPPED")), "SUCCESS")
        self.assertEqual(pr_status.ci_rollup(self._pr("NEUTRAL")), "SUCCESS")

    def test_cancelled_is_failure(self):
        self.assertEqual(pr_status.ci_rollup(self._pr("CANCELLED")), "FAILURE")
        self.assertEqual(pr_status.ci_rollup(self._pr("STALE")), "FAILURE")

    def test_pending_wins_over_success(self):
        self.assertEqual(pr_status.ci_rollup(self._pr("SUCCESS", "IN_PROGRESS")), "PENDING")

    def test_no_checks(self):
        self.assertEqual(pr_status.ci_rollup({"statusCheckRollup": []}), "none")


class ListIssuesTests(unittest.TestCase):
    def test_foreign_owner_excluded_own_owner_reclaimable(self):
        self.assertTrue(list_issues.is_excluded(["owner:claude-orch"], "opencode-muse"))
        self.assertFalse(list_issues.is_excluded(["owner:opencode-muse"], "opencode-muse"))
        self.assertTrue(list_issues.is_excluded(["in-progress"], "opencode-muse"))

    def test_dependency_numbers_captures_all_refs(self):
        self.assertEqual(
            list_issues.dependency_numbers("depends on #12 and #13"),
            {12, 13},
        )

    def test_negated_dependency_is_not_a_blocker(self):
        self.assertEqual(list_issues.dependency_numbers("not blocked by #5"), set())
        self.assertEqual(list_issues.dependency_numbers("unblocked by #5"), set())
        self.assertEqual(list_issues.dependency_numbers("blocked by #5"), {5})


class ClaimTests(unittest.TestCase):
    def test_foreign_owner_aborts_before_mutation(self):
        mutated = []
        claim.run_gh_json = lambda args: {"labels": [{"name": "owner:claude-orch"}]}
        claim.run_gh = lambda args, *a, **k: mutated.append(args)
        old = sys.argv
        sys.argv = ["claim.py", "5", "--owner", "opencode-muse", "--branch", "opencode-muse/5-x"]
        try:
            rc = claim.main()
        finally:
            sys.argv = old
        self.assertEqual(rc, 1)
        self.assertEqual(mutated, [])

    def test_partial_claim_rolls_back_owner_label(self):
        calls = []

        def fake_gh(args, *a, **k):
            calls.append(list(args))
            if args[:2] == ["issue", "comment"]:
                raise GhError("boom")
            return ""

        claim.run_gh_json = lambda args: {"labels": []}
        claim.run_gh = fake_gh
        old = sys.argv
        sys.argv = ["claim.py", "5", "--owner", "opencode-muse", "--branch", "opencode-muse/5-x"]
        try:
            rc = claim.main()
        finally:
            sys.argv = old
        self.assertEqual(rc, 2)
        self.assertIn(
            ["issue", "edit", "5", "--remove-label", "owner:opencode-muse"],
            calls,
        )


if __name__ == "__main__":
    unittest.main()
