"""Tests for the model -> coordinator id derivation (`opencode-<model>`)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import coordinator_id  # noqa: E402


class CoordinatorIdTests(unittest.TestCase):
    def test_maps_model_to_opencode_family(self):
        cases = {
            "opencode/muse-spark-1.3-contributor-free": "opencode-muse",
            "deepseek/deepseek-v4-flash": "opencode-deepseek",
            "opencode/mimo-v2.5-free": "opencode-mimo",
            "openai/gpt-5.4": "opencode-gpt",
        }
        for model, expected in cases.items():
            self.assertEqual(coordinator_id.coordinator_id(model), expected, model)

    def test_rejects_ids_that_are_not_provider_slash_model(self):
        for bad in ("", "deepseek", "deepseek/", "/deepseek-v4-flash"):
            with self.assertRaises(coordinator_id.CoordinatorIdError):
                coordinator_id.coordinator_id(bad)


if __name__ == "__main__":
    unittest.main()
